// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {AgentNFA} from "../src/AgentNFA.sol";
import {AgentAccountV2} from "../src/AgentAccountV2.sol";
import {PolicyGuardV4} from "../src/PolicyGuardV4.sol";
import {IBAP578} from "../src/interfaces/IBAP578.sol";
import {IAgentAccount} from "../src/interfaces/IAgentAccount.sol";
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
import {ERC721} from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {
    ERC1155
} from "openzeppelin-contracts/contracts/token/ERC1155/ERC1155.sol";
import {
    IERC8004IdentityRegistry
} from "../src/interfaces/IERC8004IdentityRegistry.sol";

// ─── Mock ERC-721 for testing NFT reception ───
contract MockERC721 is ERC721 {
    uint256 private _nextId;

    constructor() ERC721("MockNFT", "MNFT") {}

    function mint(address to) external returns (uint256 id) {
        id = _nextId++;
        _safeMint(to, id);
    }
}

// ─── Mock ERC-1155 for testing multi-token reception ───
contract MockERC1155 is ERC1155 {
    constructor() ERC1155("") {}

    function mint(address to, uint256 id, uint256 amount) external {
        _mint(to, id, amount, "");
    }

    function mintBatch(
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) external {
        _mintBatch(to, ids, amounts, "");
    }
}

// ─── Mock ERC-8004 Identity Registry ───
contract MockIdentityRegistry is IERC8004IdentityRegistry {
    uint256 private _nextAgentId = 1;
    mapping(uint256 => string) public agentURIs;
    mapping(uint256 => address) public agentWallets;

    function register(
        string calldata agentURI
    ) external override returns (uint256 agentId) {
        agentId = _nextAgentId++;
        agentURIs[agentId] = agentURI;
        agentWallets[agentId] = msg.sender;
    }

    function register(
        string calldata agentURI,
        MetadataEntry[] calldata
    ) external override returns (uint256 agentId) {
        agentId = _nextAgentId++;
        agentURIs[agentId] = agentURI;
        agentWallets[agentId] = msg.sender;
    }

    function setAgentURI(
        uint256 agentId,
        string calldata newURI
    ) external override {
        agentURIs[agentId] = newURI;
    }

    function setAgentWallet(
        uint256,
        address,
        uint256,
        bytes calldata
    ) external pure override {}

    function getAgentWallet(
        uint256 agentId
    ) external view override returns (address) {
        return agentWallets[agentId];
    }
}

/// @title AgentAccountV2 Tests
contract AgentAccountV2Test is Test {
    AgentNFA public nfa;
    PolicyGuardV4 public guard;
    MockERC721 public mockNFT;
    MockERC1155 public mock1155;
    MockIdentityRegistry public mockRegistry;

    address constant OWNER = address(0x1111);
    address constant RENTER = address(0x2222);
    address constant OPERATOR = address(0x3333);

    bytes32 constant POLICY_ID = keccak256("default_policy");
    string constant TOKEN_URI = "https://shll.run/metadata/1.json";

    uint256 operatorKey = 0xA11CE;
    address operatorAddr;

    function setUp() public {
        guard = new PolicyGuardV4();
        nfa = new AgentNFA(address(guard));
        mockNFT = new MockERC721();
        mock1155 = new MockERC1155();
        mockRegistry = new MockIdentityRegistry();

        operatorAddr = vm.addr(operatorKey);
    }

    function _mintDefaultAgent()
        internal
        returns (uint256 tokenId, address vault)
    {
        IBAP578.AgentMetadata memory metadata = IBAP578.AgentMetadata({
            persona: '{"role":"trader"}',
            experience: "Test agent",
            voiceHash: "",
            animationURI: "",
            vaultURI: "",
            vaultHash: bytes32(0)
        });
        tokenId = nfa.mintAgent(
            OWNER,
            POLICY_ID,
            nfa.TYPE_LLM_TRADER(),
            TOKEN_URI,
            metadata
        );
        vault = nfa.accountOf(tokenId);
    }

    // ═══════════════════════════════════════════════════════════
    //          ERC-165 INTERFACE TESTS
    // ═══════════════════════════════════════════════════════════

    function test_supportsInterface_ERC165() public {
        (, address vault) = _mintDefaultAgent();
        assertTrue(
            AgentAccountV2(payable(vault)).supportsInterface(
                type(IERC165).interfaceId
            ),
            "Should support IERC165"
        );
    }

    function test_supportsInterface_ERC721Receiver() public {
        (, address vault) = _mintDefaultAgent();
        assertTrue(
            AgentAccountV2(payable(vault)).supportsInterface(
                type(IERC721Receiver).interfaceId
            ),
            "Should support IERC721Receiver"
        );
    }

    function test_supportsInterface_ERC1155Receiver() public {
        (, address vault) = _mintDefaultAgent();
        assertTrue(
            AgentAccountV2(payable(vault)).supportsInterface(
                type(IERC1155Receiver).interfaceId
            ),
            "Should support IERC1155Receiver"
        );
    }

    function test_supportsInterface_ERC1271() public {
        (, address vault) = _mintDefaultAgent();
        assertTrue(
            AgentAccountV2(payable(vault)).supportsInterface(
                type(IERC1271).interfaceId
            ),
            "Should support IERC1271"
        );
    }

    function test_supportsInterface_IAgentAccount() public {
        (, address vault) = _mintDefaultAgent();
        assertTrue(
            AgentAccountV2(payable(vault)).supportsInterface(
                type(IAgentAccount).interfaceId
            ),
            "Should support IAgentAccount"
        );
    }

    function test_supportsInterface_unsupported() public {
        (, address vault) = _mintDefaultAgent();
        assertFalse(
            AgentAccountV2(payable(vault)).supportsInterface(
                bytes4(0xdeadbeef)
            ),
            "Should not support random interface"
        );
    }

    // ═══════════════════════════════════════════════════════════
    //          ERC-721 RECEIVER TESTS
    // ═══════════════════════════════════════════════════════════

    function test_receiveERC721() public {
        (, address vault) = _mintDefaultAgent();

        // safeMint an NFT directly to the vault — should NOT revert
        uint256 nftId = mockNFT.mint(vault);
        assertEq(mockNFT.ownerOf(nftId), vault, "Vault should own the NFT");
    }

    // ═══════════════════════════════════════════════════════════
    //          ERC-1155 RECEIVER TESTS
    // ═══════════════════════════════════════════════════════════

    function test_receiveERC1155() public {
        (, address vault) = _mintDefaultAgent();

        mock1155.mint(vault, 1, 100);
        assertEq(
            mock1155.balanceOf(vault, 1),
            100,
            "Vault should hold 100 tokens"
        );
    }

    function test_receiveERC1155Batch() public {
        (, address vault) = _mintDefaultAgent();

        uint256[] memory ids = new uint256[](2);
        ids[0] = 10;
        ids[1] = 20;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 50;
        amounts[1] = 75;

        mock1155.mintBatch(vault, ids, amounts);
        assertEq(mock1155.balanceOf(vault, 10), 50);
        assertEq(mock1155.balanceOf(vault, 20), 75);
    }

    // ═══════════════════════════════════════════════════════════
    //          ERC-1271 SIGNATURE VALIDATION TESTS
    // ═══════════════════════════════════════════════════════════

    function test_isValidSignature_owner() public {
        // Use a real key pair (foundry requires a private key for vm.sign)
        uint256 ownerKey = 0xB0B;
        address ownerAddr = vm.addr(ownerKey);

        // Mint agent with ownerAddr
        IBAP578.AgentMetadata memory metadata = IBAP578.AgentMetadata({
            persona: '{"role":"trader"}',
            experience: "Test",
            voiceHash: "",
            animationURI: "",
            vaultURI: "",
            vaultHash: bytes32(0)
        });
        uint256 tid = nfa.mintAgent(
            ownerAddr,
            POLICY_ID,
            nfa.TYPE_LLM_TRADER(),
            TOKEN_URI,
            metadata
        );
        address v2 = nfa.accountOf(tid);

        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, hash);
        bytes memory sig = abi.encodePacked(r, s, v);

        bytes4 result = AgentAccountV2(payable(v2)).isValidSignature(hash, sig);
        assertEq(result, bytes4(0x1626ba7e), "Owner signature should be valid");
    }

    function test_isValidSignature_invalidSigner() public {
        (, address vault) = _mintDefaultAgent();

        bytes32 hash = keccak256("test message");
        uint256 randomKey = 0xDEAD;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(randomKey, hash);
        bytes memory sig = abi.encodePacked(r, s, v);

        bytes4 result = AgentAccountV2(payable(vault)).isValidSignature(
            hash,
            sig
        );
        assertEq(
            result,
            bytes4(0xffffffff),
            "Random signer should be rejected"
        );
    }

    // ═══════════════════════════════════════════════════════════
    //          CORE FUNCTIONALITY REGRESSION TESTS
    // ═══════════════════════════════════════════════════════════

    function test_vaultIsV2() public {
        (, address vault) = _mintDefaultAgent();

        // Verify it's actually a V2 by checking interface support
        assertTrue(
            AgentAccountV2(payable(vault)).supportsInterface(
                type(IERC165).interfaceId
            ),
            "Vault should be V2"
        );
    }

    function test_depositAndWithdrawNative() public {
        (, address vault) = _mintDefaultAgent();

        // Fund the vault
        vm.deal(address(this), 1 ether);
        (bool ok, ) = vault.call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(vault.balance, 1 ether);

        // Withdraw as owner
        vm.prank(OWNER);
        AgentAccountV2(payable(vault)).withdrawNative(0.5 ether, OWNER);
        assertEq(vault.balance, 0.5 ether);
    }

    function test_executeCall_onlyNFA() public {
        (, address vault) = _mintDefaultAgent();

        // Non-NFA should be rejected
        vm.expectRevert();
        AgentAccountV2(payable(vault)).executeCall(address(0), 0, "");
    }

    // ═══════════════════════════════════════════════════════════
    //          ERC-8004 AUTO-REGISTRATION TESTS
    // ═══════════════════════════════════════════════════════════

    function test_mintAgent_withRegistry() public {
        nfa.setIdentityRegistry(address(mockRegistry));

        IBAP578.AgentMetadata memory metadata = IBAP578.AgentMetadata({
            persona: '{"role":"trader"}',
            experience: "Test",
            voiceHash: "",
            animationURI: "",
            vaultURI: "",
            vaultHash: bytes32(0)
        });

        uint256 tokenId = nfa.mintAgent(
            OWNER,
            POLICY_ID,
            nfa.TYPE_LLM_TRADER(),
            TOKEN_URI,
            metadata
        );

        // Should have stored the ERC-8004 agentId
        uint256 agentId = nfa.erc8004AgentId(tokenId);
        assertTrue(agentId > 0, "ERC-8004 agentId should be set");

        // Registry should have the URI
        assertEq(
            mockRegistry.agentURIs(agentId),
            TOKEN_URI,
            "Registry URI should match"
        );
    }

    function test_mintAgent_withoutRegistry() public {
        // identityRegistry is address(0) by default — should NOT revert
        IBAP578.AgentMetadata memory metadata = IBAP578.AgentMetadata({
            persona: '{"role":"trader"}',
            experience: "Test",
            voiceHash: "",
            animationURI: "",
            vaultURI: "",
            vaultHash: bytes32(0)
        });

        uint256 tokenId = nfa.mintAgent(
            OWNER,
            POLICY_ID,
            nfa.TYPE_LLM_TRADER(),
            TOKEN_URI,
            metadata
        );

        // agentId should be 0 (not registered)
        assertEq(
            nfa.erc8004AgentId(tokenId),
            0,
            "Should not register without registry"
        );
    }

    function test_updateAgentProfile() public {
        nfa.setIdentityRegistry(address(mockRegistry));

        IBAP578.AgentMetadata memory metadata = IBAP578.AgentMetadata({
            persona: '{"role":"trader"}',
            experience: "Test",
            voiceHash: "",
            animationURI: "",
            vaultURI: "",
            vaultHash: bytes32(0)
        });

        uint256 tokenId = nfa.mintAgent(
            OWNER,
            POLICY_ID,
            nfa.TYPE_LLM_TRADER(),
            TOKEN_URI,
            metadata
        );
        uint256 agentId = nfa.erc8004AgentId(tokenId);

        string memory newURI = "https://shll.run/metadata/updated.json";
        vm.prank(OWNER);
        nfa.updateAgentProfile(tokenId, newURI);

        assertEq(
            mockRegistry.agentURIs(agentId),
            newURI,
            "Registry URI should be updated"
        );
    }

    function test_updateAgentProfile_onlyOwner() public {
        nfa.setIdentityRegistry(address(mockRegistry));

        IBAP578.AgentMetadata memory metadata = IBAP578.AgentMetadata({
            persona: '{"role":"trader"}',
            experience: "Test",
            voiceHash: "",
            animationURI: "",
            vaultURI: "",
            vaultHash: bytes32(0)
        });

        uint256 tokenId = nfa.mintAgent(
            OWNER,
            POLICY_ID,
            nfa.TYPE_LLM_TRADER(),
            TOKEN_URI,
            metadata
        );

        vm.prank(RENTER);
        vm.expectRevert();
        nfa.updateAgentProfile(tokenId, "https://malicious.com");
    }
}
