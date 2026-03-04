// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AgentNFA} from "../src/AgentNFA.sol";
import {LearningModule} from "../src/LearningModule.sol";

/// @title DeployV4 — Deploy AgentNFA V4 + LearningModule
/// @notice ProtocolRegistry already deployed separately. This script only deploys
///         AgentNFA + LearningModule and configures cross-references.
contract DeployV4 is Script {
    function run() external {
        // --- Existing addresses ---
        address policyGuardV4 = 0x25d17eA0e3Bcb8CA08a2BFE917E817AFc05dbBB3;
        address listingManager = vm.envAddress("LISTING_MANAGER_V2");
        address subscriptionManager = vm.envAddress("SUBSCRIPTION_MANAGER");
        address identityRegistry = address(
            0x8004A169FB4a3325136EB29fA0ceB6D2e539a432
        );

        vm.startBroadcast();

        // 1. Deploy AgentNFA V4
        AgentNFA nfa = new AgentNFA(policyGuardV4);
        console.log("AgentNFA V4:", address(nfa));

        // 2. Deploy LearningModule (bound to new NFA)
        LearningModule learning = new LearningModule(address(nfa));
        console.log("LearningModule:", address(learning));

        // 3. Configure AgentNFA
        nfa.setListingManager(listingManager);
        nfa.setSubscriptionManager(subscriptionManager);
        nfa.setIdentityRegistry(identityRegistry);
        nfa.setLearningModule(address(learning));
        console.log("AgentNFA configured");

        vm.stopBroadcast();

        // --- Summary ---
        console.log("\n=== V4.0 Deployment ===");
        console.log("AgentNFA V4:         ", address(nfa));
        console.log("LearningModule:      ", address(learning));
        console.log("PolicyGuardV4:       ", policyGuardV4);
        console.log("ListingManager:      ", listingManager);
        console.log("SubscriptionManager: ", subscriptionManager);
        console.log("\nPost-deploy:");
        console.log("1. ListingManager.setAgentNFA(new NFA)");
        console.log("2. SubscriptionManager.setAgentNFA(new NFA)");
        console.log("3. Update .env AGENT_NFA");
    }
}
