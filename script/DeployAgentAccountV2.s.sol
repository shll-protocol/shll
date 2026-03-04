// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AgentAccountV2} from "../src/AgentAccountV2.sol";

/// @title DeployAgentAccountV2 — Standalone deployment for testing
/// @notice In production, AgentAccountV2 is deployed automatically by AgentNFA.mintAgent()
contract DeployAgentAccountV2 is Script {
    function run() external {
        address nfa = vm.envAddress("AGENT_NFA");
        uint256 tokenId = vm.envUint("TOKEN_ID");

        vm.startBroadcast();

        AgentAccountV2 account = new AgentAccountV2(nfa, tokenId);
        console.log("AgentAccountV2 deployed at:", address(account));
        console.log("  nfa:", nfa);
        console.log("  tokenId:", tokenId);

        vm.stopBroadcast();
    }
}
