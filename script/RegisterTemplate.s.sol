// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AgentNFA} from "../src/AgentNFA.sol";

/// @title RegisterTemplate — Register token #0 as template
contract RegisterTemplate is Script {
    function run() external {
        AgentNFA agentNFA = AgentNFA(vm.envAddress("AGENT_NFA"));

        console.log("Token #0 owner:", agentNFA.ownerOf(0));
        console.log("Caller (msg.sender will be):", msg.sender);

        vm.startBroadcast();

        agentNFA.registerTemplate(0, bytes32(uint256(1)));
        console.log("Token #0 registered as template!");

        vm.stopBroadcast();
    }
}
