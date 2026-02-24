// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {DeFiGuardPolicy} from "../src/policies/DeFiGuardPolicy.sol";
import {PolicyGuardV4} from "../src/PolicyGuardV4.sol";

/// @title UpgradeDeFiGuardV3 — Fix approve target whitelist bypass
/// @dev Redeploys DeFiGuardPolicy with approve/decreaseAllowance bypass for target whitelist.
///
///   forge script script/UpgradeDeFiGuardV3.s.sol \
///     --account deployer --rpc-url https://bsc-dataseed1.binance.org \
///     --broadcast --gas-price 3000000000 --skip-simulation -vvv
contract UpgradeDeFiGuardV3 is Script {
    bytes32 constant TEMPLATE_LLM = keccak256("llm_trader_v3");

    address constant GUARD = 0x25d17eA0e3Bcb8CA08a2BFE917E817AFc05dbBB3;
    address constant NFA = 0xE98DCdbf370D7b52c9A2b88F79bEF514A5375a2b;

    // Current DeFiGuardPolicy (deployed earlier today, at last index)
    // Template order: [0]=Cooldown, [1]=SpendingLimit, [2]=ReceiverGuard, [3]=DexWL, [4]=DeFiGuard
    uint256 constant DEFI_GUARD_INDEX = 4;

    // Targets
    address constant PANCAKE_ROUTER =
        0x10ED43C718714eb63d5aA57B78B54704E256024E;
    address constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address constant USDT = 0x55d398326f99059fF775485246999027B3197955;

    // Selectors
    bytes4 constant SEL_APPROVE = 0x095ea7b3;
    bytes4 constant SEL_SWAP_EXACT_TOKENS = 0x38ed1739;
    bytes4 constant SEL_SWAP_TOKENS_EXACT = 0x8803dbee;
    bytes4 constant SEL_SWAP_EXACT_ETH = 0x7ff36ab5;
    bytes4 constant SEL_SWAP_TOKENS_EXACT_ETH = 0x4a25d94a;
    bytes4 constant SEL_SWAP_EXACT_TOKENS_ETH = 0x791ac947;
    bytes4 constant SEL_SWAP_EXACT_TOKENS_FEE = 0x5c11d795;
    bytes4 constant SEL_SWAP_EXACT_ETH_FEE = 0xb6f9de95;
    bytes4 constant SEL_WBNB_DEPOSIT = 0xd0e30db0;
    bytes4 constant SEL_WBNB_WITHDRAW = 0x2e1a7d4d;
    bytes4 constant SEL_DECREASE_ALLOWANCE = 0xa457c2d7;

    function run() external {
        vm.startBroadcast();

        // 1. Deploy new DeFiGuardPolicy
        DeFiGuardPolicy newDeFiGuard = new DeFiGuardPolicy(GUARD, NFA);
        console.log("[1/6] New DeFiGuardPolicy:", address(newDeFiGuard));

        // 2. Approve in PolicyGuardV4
        PolicyGuardV4(GUARD).approvePolicyContract(address(newDeFiGuard));
        console.log("[2/6] Approved");

        // 3. Remove old DeFiGuardPolicy (index 4)
        PolicyGuardV4(GUARD).removeTemplatePolicy(
            TEMPLATE_LLM,
            DEFI_GUARD_INDEX
        );
        console.log("[3/6] Removed old from template");

        // 4. Add new
        PolicyGuardV4(GUARD).addTemplatePolicy(
            TEMPLATE_LLM,
            address(newDeFiGuard)
        );
        console.log("[4/6] Added new to template");

        // 5. Configure global targets (PancakeRouter + WBNB + USDT)
        newDeFiGuard.addGlobalTarget(PANCAKE_ROUTER);
        newDeFiGuard.addGlobalTarget(WBNB);
        newDeFiGuard.addGlobalTarget(USDT);
        console.log("[5/6] 3 global targets added");

        // 6. Configure selectors
        newDeFiGuard.addSelector(SEL_APPROVE);
        newDeFiGuard.addSelector(SEL_SWAP_EXACT_TOKENS);
        newDeFiGuard.addSelector(SEL_SWAP_TOKENS_EXACT);
        newDeFiGuard.addSelector(SEL_SWAP_EXACT_ETH);
        newDeFiGuard.addSelector(SEL_SWAP_TOKENS_EXACT_ETH);
        newDeFiGuard.addSelector(SEL_SWAP_EXACT_TOKENS_ETH);
        newDeFiGuard.addSelector(SEL_SWAP_EXACT_TOKENS_FEE);
        newDeFiGuard.addSelector(SEL_SWAP_EXACT_ETH_FEE);
        newDeFiGuard.addSelector(SEL_WBNB_DEPOSIT);
        newDeFiGuard.addSelector(SEL_WBNB_WITHDRAW);
        newDeFiGuard.addSelector(SEL_DECREASE_ALLOWANCE);
        console.log("[6/6] 11 selectors configured");

        vm.stopBroadcast();

        console.log("");
        console.log("New DeFiGuardPolicy:", address(newDeFiGuard));
        console.log("Update RESOURCE-MAP.yml");
    }
}
