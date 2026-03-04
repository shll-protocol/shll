// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    ReentrancyGuard
} from "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    IERC165
} from "openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";
import {
    IERC721Receiver
} from "openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";
import {
    IERC721
} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {
    IERC1155Receiver
} from "openzeppelin-contracts/contracts/token/ERC1155/IERC1155Receiver.sol";
import {
    IERC1271
} from "openzeppelin-contracts/contracts/interfaces/IERC1271.sol";
import {
    ECDSA
} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {IAgentAccount} from "./interfaces/IAgentAccount.sol";
import {Errors} from "./libs/Errors.sol";

/// @title AgentAccountV2 — Agent vault with identity, NFT receiver, and signature capabilities
/// @notice V2 extends V1 with ERC-165/721Receiver/1155Receiver/1271 for agent identity support
/// @dev Enables: NFT reception (Agent Identity), contract signing (Permit2/ERC-8004),
///      and interface discovery. Core execute/deposit/withdraw logic unchanged from V1.
contract AgentAccountV2 is
    IAgentAccount,
    IERC165,
    IERC721Receiver,
    IERC1155Receiver,
    IERC1271,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;

    /// @notice ERC-1271 magic value for valid signatures
    bytes4 private constant ERC1271_MAGIC_VALUE = 0x1626ba7e;

    /// @notice The AgentNFA contract that controls this account
    address public immutable nfa;

    /// @notice The token ID this account is bound to
    uint256 public immutable tokenId;

    // ─── Events ───
    event Deposited(
        address indexed token,
        address indexed from,
        uint256 amount
    );
    event WithdrawnToken(
        address indexed token,
        address indexed to,
        uint256 amount
    );
    event WithdrawnNative(address indexed to, uint256 amount);
    event CallExecuted(address indexed target, uint256 value, bool success);

    constructor(address _nfa, uint256 _tokenId) {
        if (_nfa == address(0)) revert Errors.ZeroAddress();
        nfa = _nfa;
        tokenId = _tokenId;
    }

    /// @notice Receive native currency (BNB)
    receive() external payable {}

    // ═══════════════════════════════════════════════════════════
    //                    ERC-165 INTROSPECTION
    // ═══════════════════════════════════════════════════════════

    /// @notice Declare supported interfaces for on-chain discovery
    function supportsInterface(
        bytes4 interfaceId
    ) external pure override(IERC165) returns (bool) {
        return
            interfaceId == type(IERC165).interfaceId ||
            interfaceId == type(IERC721Receiver).interfaceId ||
            interfaceId == type(IERC1155Receiver).interfaceId ||
            interfaceId == type(IERC1271).interfaceId ||
            interfaceId == type(IAgentAccount).interfaceId;
    }

    // ═══════════════════════════════════════════════════════════
    //                    ERC-721 RECEIVER
    // ═══════════════════════════════════════════════════════════

    /// @notice Accept ERC-721 NFTs (Agent Identity, BAP-578 NFTs, etc.)
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override(IERC721Receiver) returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    // ═══════════════════════════════════════════════════════════
    //                    ERC-1155 RECEIVER
    // ═══════════════════════════════════════════════════════════

    /// @notice Accept single ERC-1155 token transfers
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure override(IERC1155Receiver) returns (bytes4) {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    /// @notice Accept batch ERC-1155 token transfers
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure override(IERC1155Receiver) returns (bytes4) {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    // ═══════════════════════════════════════════════════════════
    //                    ERC-1271 SIGNATURE VALIDATION
    // ═══════════════════════════════════════════════════════════

    /// @notice Validate signatures on behalf of this vault
    /// @dev Accepts signatures from the current operator or renter of the bound NFA token.
    ///      Used by Permit2, ERC-8004 setAgentWallet, and other signature-dependent protocols.
    /// @param hash The hash that was signed
    /// @param signature The signature to verify
    /// @return magicValue ERC1271_MAGIC_VALUE if valid, 0xffffffff if invalid
    function isValidSignature(
        bytes32 hash,
        bytes calldata signature
    ) external view override(IERC1271) returns (bytes4) {
        (address signer, ECDSA.RecoverError err) = ECDSA.tryRecover(
            hash,
            signature
        );
        if (err != ECDSA.RecoverError.NoError) return bytes4(0xffffffff);

        // Interface for reading operator/user from AgentNFA
        // operatorOf returns address(0) if expired
        (bool okOp, bytes memory dataOp) = nfa.staticcall(
            abi.encodeWithSignature("operatorOf(uint256)", tokenId)
        );
        if (okOp && dataOp.length == 32) {
            address operator = abi.decode(dataOp, (address));
            if (operator != address(0) && signer == operator) {
                return ERC1271_MAGIC_VALUE;
            }
        }

        // userOf returns address(0) if expired
        (bool okUser, bytes memory dataUser) = nfa.staticcall(
            abi.encodeWithSignature("userOf(uint256)", tokenId)
        );
        if (okUser && dataUser.length == 32) {
            address user = abi.decode(dataUser, (address));
            if (user != address(0) && signer == user) {
                return ERC1271_MAGIC_VALUE;
            }
        }

        // Also accept owner signatures (for non-instance templates)
        (bool okOwner, bytes memory dataOwner) = nfa.staticcall(
            abi.encodeWithSignature("ownerOf(uint256)", tokenId)
        );
        if (okOwner && dataOwner.length == 32) {
            address owner = abi.decode(dataOwner, (address));
            if (signer == owner) {
                return ERC1271_MAGIC_VALUE;
            }
        }

        return bytes4(0xffffffff);
    }

    // ═══════════════════════════════════════════════════════════
    //                    DEPOSIT
    // ═══════════════════════════════════════════════════════════

    /// @inheritdoc IAgentAccount
    function depositToken(address token, uint256 amount) external nonReentrant {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        emit Deposited(token, msg.sender, amount);
    }

    // ═══════════════════════════════════════════════════════════
    //                    WITHDRAW
    // ═══════════════════════════════════════════════════════════

    /// @inheritdoc IAgentAccount
    function withdrawToken(
        address token,
        uint256 amount,
        address to
    ) external nonReentrant {
        _checkWithdrawPermission(to);
        IERC20(token).safeTransfer(to, amount);
        emit WithdrawnToken(token, to, amount);
    }

    /// @inheritdoc IAgentAccount
    function withdrawNative(uint256 amount, address to) external nonReentrant {
        _checkWithdrawPermission(to);
        if (amount > address(this).balance) revert Errors.InsufficientBalance();
        (bool success, ) = to.call{value: amount}("");
        if (!success) revert Errors.ExecutionFailed();
        emit WithdrawnNative(to, amount);
    }

    // ═══════════════════════════════════════════════════════════
    //                    EXECUTE (NFA only)
    // ═══════════════════════════════════════════════════════════

    /// @inheritdoc IAgentAccount
    function executeCall(
        address target,
        uint256 value,
        bytes calldata data
    ) external nonReentrant returns (bool ok, bytes memory result) {
        if (msg.sender != nfa) revert Errors.OnlyNFA();
        (ok, result) = target.call{value: value}(data);
        emit CallExecuted(target, value, ok);
    }

    // ═══════════════════════════════════════════════════════════
    //                    INTERNAL
    // ═══════════════════════════════════════════════════════════

    /// @dev Check that msg.sender is owner and recipient is owner
    function _checkWithdrawPermission(address to) internal view {
        address owner = IERC721(nfa).ownerOf(tokenId);
        if (msg.sender != owner) revert Errors.Unauthorized();
        if (to != owner) revert Errors.InvalidWithdrawRecipient();
    }
}
