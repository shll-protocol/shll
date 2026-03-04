// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {SubscriptionManager} from "../src/SubscriptionManager.sol";

/// @title DeploySM — Deploy fresh SubscriptionManager and configure it
contract DeploySM is Script {
    address constant NFA = 0xfFbf69F6FdE7710E4298C7dF7B03A35136fA15B3;
    address constant LISTING = 0x1f9CE85bD0FF75acc3D92eB79f1Eb472f0865071;

    function run() external {
        vm.startBroadcast();

        SubscriptionManager sm = new SubscriptionManager();
        console.log("New SubscriptionManager:", address(sm));

        // Configure
        sm.setAgentNFA(NFA);
        sm.setListingManager(LISTING);
        console.log("  agentNFA:", sm.agentNFA());
        console.log("  listingManager:", sm.listingManager());

        vm.stopBroadcast();
    }
}
