// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAgentAccount} from "./IAgentAccount.sol";
import {
    IERC165
} from "openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";
import {
    IERC721Receiver
} from "openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";
import {
    IERC1155Receiver
} from "openzeppelin-contracts/contracts/token/ERC1155/IERC1155Receiver.sol";
import {
    IERC1271
} from "openzeppelin-contracts/contracts/interfaces/IERC1271.sol";

/// @title IAgentAccountV2
/// @notice Extended vault interface with identity, NFT receiver, and signature capabilities
interface IAgentAccountV2 is
    IAgentAccount,
    IERC165,
    IERC721Receiver,
    IERC1155Receiver,
    IERC1271
{
    /// @notice The AgentNFA contract that controls this account
    function nfa() external view returns (address);

    /// @notice The token ID this account is bound to
    function tokenId() external view returns (uint256);
}
