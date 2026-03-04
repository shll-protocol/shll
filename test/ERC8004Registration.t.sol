// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {AgentNFA} from "../src/AgentNFA.sol";
import {AgentAccountV2} from "../src/AgentAccountV2.sol";
import {IBAP578} from "../src/interfaces/IBAP578.sol";

/// @title TestERC8004Final — Root cause analysis
contract TestERC8004Final is Test {
    address constant REGISTRY = 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432;
    address constant POLICY_GUARD = 0x25d17eA0e3Bcb8CA08a2BFE917E817AFc05dbBB3;
    address deployer = makeAddr("deployer");

    /// Test: Call register() directly from vault address (bypass executeCall)
    function test_prankedVaultCallsRegistry() public {
        vm.startPrank(deployer);
        AgentNFA nfa = new AgentNFA(POLICY_GUARD);

        IBAP578.AgentMetadata memory meta = IBAP578.AgentMetadata({
            persona: "",
            experience: "",
            voiceHash: "",
            animationURI: "",
            vaultURI: "",
            vaultHash: bytes32(0)
        });
        uint256 tokenId = nfa.mintAgent(
            deployer,
            bytes32(uint256(1)),
            keccak256("TYPE_LLM_TRADER"),
            "",
            meta
        );
        address vault = nfa.accountOf(tokenId);
        console.log("Vault:", vault);
        console.log("Vault code size:", vault.code.length);
        vm.stopPrank();

        // Prank AS the vault — simulate msg.sender = vault calling registry directly
        vm.prank(vault);
        bytes memory callData = abi.encodeWithSelector(
            bytes4(keccak256("register(string)")),
            "test-uri"
        );
        (bool ok, bytes memory result) = REGISTRY.call(callData);
        console.log("Vault->Registry direct call OK:", ok);
        if (ok && result.length >= 32) {
            uint256 agentId = abi.decode(result, (uint256));
            console.log("agentId:", agentId);
        } else if (!ok) {
            console.log("Revert data length:", result.length);
            if (result.length >= 4) {
                bytes4 sig;
                assembly {
                    sig := mload(add(result, 32))
                }
                console.logBytes4(sig);
            }
            console.logBytes(result);
        }
    }

    /// Test: Call register() from EOA
    function test_eoaCallsRegistry() public {
        vm.prank(deployer);
        bytes memory callData = abi.encodeWithSelector(
            bytes4(keccak256("register(string)")),
            "test-uri"
        );
        (bool ok, bytes memory result) = REGISTRY.call(callData);
        console.log("EOA->Registry call OK:", ok);
        if (ok && result.length >= 32) {
            uint256 agentId = abi.decode(result, (uint256));
            console.log("agentId:", agentId);
        }
    }

    /// Test: Call register() with no-arg version
    function test_noArgRegister() public {
        vm.startPrank(deployer);
        AgentNFA nfa = new AgentNFA(POLICY_GUARD);
        IBAP578.AgentMetadata memory meta = IBAP578.AgentMetadata({
            persona: "",
            experience: "",
            voiceHash: "",
            animationURI: "",
            vaultURI: "",
            vaultHash: bytes32(0)
        });
        uint256 tokenId = nfa.mintAgent(
            deployer,
            bytes32(uint256(1)),
            keccak256("TYPE_LLM_TRADER"),
            "",
            meta
        );
        address vault = nfa.accountOf(tokenId);
        vm.stopPrank();

        // No-arg register()
        vm.prank(vault);
        (bool ok, bytes memory result) = REGISTRY.call(
            abi.encodeWithSignature("register()")
        );
        console.log("Vault->Registry register() OK:", ok);
        if (ok && result.length >= 32) {
            console.log("agentId:", abi.decode(result, (uint256)));
        }
    }
}
