// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AgentNFAExtensions} from "../src/AgentNFAExtensions.sol";
import {SpendingLimitPolicy} from "../src/policies/SpendingLimitPolicy.sol";
import {PolicyGuardV4} from "../src/PolicyGuardV4.sol";

/// @title UpgradeV32Extensions — Deploy AgentNFAExtensions + Replace SpendingLimitPolicy
/// @notice Targeted upgrade: only deploys the 2 changed contracts, wires into existing system.
///
/// @dev Usage (BSC Testnet):
///   forge script script/UpgradeV32Extensions.s.sol \
///     --rpc-url $RPC_URL --broadcast --gas-price 5000000000 -vvv
///
/// Required .env:
///   PRIVATE_KEY, AGENT_NFA, POLICY_GUARD_V4, SPENDING_LIMIT (old),
///   ROUTER_ADDRESS
contract UpgradeV32Extensions is Script {
    bytes32 constant TEMPLATE_LLM = keccak256("llm_trader_v3");

    function run() external {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", uint256(0));
        address deployer = deployerKey != 0 ? vm.addr(deployerKey) : msg.sender;

        // Existing contract addresses from .env
        address agentNFA = vm.envAddress("AGENT_NFA");
        address guardAddr = vm.envAddress("POLICY_GUARD_V4");
        address oldSpendingLimit = vm.envAddress("SPENDING_LIMIT");
        address router = vm.envAddress("ROUTER_ADDRESS");

        console.log("========================================================");
        console.log("  SHLL V3.2 Extensions Upgrade (Targeted)");
        console.log("========================================================");
        console.log("Deployer           :", deployer);
        console.log("Existing AgentNFA  :", agentNFA);
        console.log("Existing Guard     :", guardAddr);
        console.log("Old SpendingLimit  :", oldSpendingLimit);
        console.log("Router             :", router);
        console.log("========================================================");
        console.log("");

        PolicyGuardV4 guard = PolicyGuardV4(guardAddr);

        // ── Pre-flight: find old SpendingLimitPolicy index in template ──
        address[] memory tplPolicies = guard.getTemplatePolicies(TEMPLATE_LLM);
        console.log("Template LLM has", tplPolicies.length, "policies:");
        uint256 oldIndex = type(uint256).max;
        for (uint256 i = 0; i < tplPolicies.length; i++) {
            console.log("  [", i, "]", tplPolicies[i]);
            if (tplPolicies[i] == oldSpendingLimit) {
                oldIndex = i;
            }
        }
        require(
            oldIndex != type(uint256).max,
            "Old SpendingLimitPolicy not found in template"
        );
        console.log("Old SpendingLimitPolicy at index:", oldIndex);
        console.log("");

        if (deployerKey != 0) {
            vm.startBroadcast(deployerKey);
        } else {
            vm.startBroadcast();
        }

        // ── Step 1: Deploy AgentNFAExtensions (new, standalone) ──
        AgentNFAExtensions extensions = new AgentNFAExtensions(agentNFA);
        console.log("[1/5] AgentNFAExtensions deployed:", address(extensions));

        // ── Step 2: Deploy new SpendingLimitPolicy ──
        SpendingLimitPolicy newSpendingLimit = new SpendingLimitPolicy(
            guardAddr,
            agentNFA
        );
        console.log(
            "[2/5] New SpendingLimitPolicy deployed:",
            address(newSpendingLimit)
        );

        // ── Step 3: Swap SpendingLimitPolicy in PolicyGuard ──
        // 3a. Remove old from template (by index)
        guard.removeTemplatePolicy(TEMPLATE_LLM, oldIndex);
        console.log(
            "[3/5] Removed old SpendingLimitPolicy from LLM template (index",
            oldIndex,
            ")"
        );

        // 3b. Revoke old policy
        guard.revokePolicyContract(oldSpendingLimit);
        console.log("      Revoked old SpendingLimitPolicy");

        // 3c. Approve new policy
        guard.approvePolicyContract(address(newSpendingLimit));
        console.log("      Approved new SpendingLimitPolicy");

        // 3d. Add new to template
        guard.addTemplatePolicy(TEMPLATE_LLM, address(newSpendingLimit));
        console.log("      Added new SpendingLimitPolicy to LLM template");

        // ── Step 4: Re-configure SpendingLimitPolicy ceilings ──
        newSpendingLimit.setTemplateCeiling(
            TEMPLATE_LLM,
            10 ether,
            50 ether,
            500
        );
        console.log("[4/5] Ceiling set: 10 BNB/tx, 50 BNB/day, 500 bps");

        newSpendingLimit.setTemplateApproveCeiling(TEMPLATE_LLM, 10 ether);
        console.log("      Approve ceiling: 10 BNB");

        newSpendingLimit.setApprovedSpender(router, true);
        console.log("      Approved spender: Router");

        vm.stopBroadcast();

        // ── Step 5: Summary ──
        console.log("");
        console.log("========================================================");
        console.log("  UPGRADE COMPLETE");
        console.log("========================================================");
        console.log("");
        console.log("NEW contracts:");
        console.log("  AgentNFAExtensions :", address(extensions));
        console.log("  SpendingLimitPolicy:", address(newSpendingLimit));
        console.log("");
        console.log("OLD contract (revoked):");
        console.log("  SpendingLimitPolicy:", oldSpendingLimit);
        console.log("");
        console.log("ENV update:");
        console.log(
            string.concat(
                "SPENDING_LIMIT=",
                vm.toString(address(newSpendingLimit))
            )
        );
        console.log(
            string.concat(
                "AGENT_NFA_EXTENSIONS=",
                vm.toString(address(extensions))
            )
        );
        console.log("");
        console.log("[5/5] Done. Update .env with new addresses above.");
        console.log("========================================================");
    }
}
