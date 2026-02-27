// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {DeFiGuardPolicyV2} from "../src/policies/DeFiGuardPolicyV2.sol";
import {PolicyGuardV4} from "../src/PolicyGuardV4.sol";

/// @title UpgradeDeFiGuardV2 — Deploy DeFiGuardPolicyV2 with Selector Packs
/// @notice Replaces existing DeFiGuardPolicy with V2 that supports:
///         - Selector Packs: Owner creates named packs (LENDING, STAKING, V3_SWAP)
///         - Renter self-service: enable/disable packs per-instance
///         - Pack targets: Venus vTokens bundled with LENDING pack
///
/// @dev Usage:
///   forge script script/UpgradeDeFiGuardV2.s.sol \
///     --account deployer --rpc-url https://bsc-dataseed1.binance.org \
///     --broadcast --gas-price 3000000000 --skip-simulation -vvv
contract UpgradeDeFiGuardV2 is Script {
    bytes32 constant TEMPLATE_LLM = keccak256("llm_trader_v3");

    address constant GUARD = 0x25d17eA0e3Bcb8CA08a2BFE917E817AFc05dbBB3;
    address constant NFA = 0xE98DCdbf370D7b52c9A2b88F79bEF514A5375a2b;

    // Current DeFiGuardPolicy V1 — index 4 in template
    // Template order: [0]=Cooldown, [1]=SpendingLimit, [2]=ReceiverGuard, [3]=DexWL, [4]=DeFiGuard
    uint256 constant DEFI_GUARD_INDEX = 4;

    // ── Global Targets ──────────────────────────────────────
    address constant PANCAKE_V2_ROUTER =
        0x10ED43C718714eb63d5aA57B78B54704E256024E;
    address constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address constant USDT = 0x55d398326f99059fF775485246999027B3197955;

    // New in V2: PancakeSwap V3 SmartRouter
    address constant PANCAKE_V3_SMART_ROUTER =
        0x13f4EA83D0bd40E75C8222255bc855a974568Dd4;

    // ── Venus Protocol Addresses ────────────────────────────
    address constant VENUS_VBNB = 0xA07c5b74C9B40447a954e1466938b865b6BBea36;
    address constant VENUS_VUSDT = 0xfD5840Cd36d94D7229439859C0112a4185BC0255;
    address constant VENUS_VUSDC = 0xecA88125a5ADbe82614ffC12D0DB554E2e2867C8;
    address constant VENUS_VBUSD = 0x95c78222B3D6e262426483D42CfA53685A67Ab9D;

    // ── Global Selectors (always active) ────────────────────
    bytes4 constant SEL_APPROVE = 0x095ea7b3;
    bytes4 constant SEL_DECREASE_ALLOWANCE = 0xa457c2d7;
    bytes4 constant SEL_SWAP_EXACT_TOKENS = 0x38ed1739;
    bytes4 constant SEL_SWAP_TOKENS_EXACT = 0x8803dbee;
    bytes4 constant SEL_SWAP_EXACT_ETH = 0x7ff36ab5;
    bytes4 constant SEL_SWAP_TOKENS_EXACT_ETH = 0x4a25d94a;
    bytes4 constant SEL_SWAP_EXACT_TOKENS_ETH = 0x791ac947;
    bytes4 constant SEL_SWAP_EXACT_TOKENS_FEE = 0x5c11d795;
    bytes4 constant SEL_SWAP_EXACT_ETH_FEE = 0xb6f9de95;
    bytes4 constant SEL_WBNB_DEPOSIT = 0xd0e30db0;
    bytes4 constant SEL_WBNB_WITHDRAW = 0x2e1a7d4d;

    // ── Pack Selectors ──────────────────────────────────────
    // Lending (Venus)
    bytes4 constant SEL_MINT = 0xa0712d68; // mint(uint256)
    bytes4 constant SEL_MINT_BNB = 0x1249c58b; // mint() payable (vBNB)
    bytes4 constant SEL_REDEEM = 0xdb006a75; // redeem(uint256)
    bytes4 constant SEL_REDEEM_UNDERLYING = 0x852a12e3; // redeemUnderlying(uint256)
    bytes4 constant SEL_BORROW = 0xc5ebeaec; // borrow(uint256)
    bytes4 constant SEL_REPAY_BORROW = 0x0e752702; // repayBorrow(uint256)

    // V3 Swap
    bytes4 constant SEL_EXACT_INPUT_SINGLE = 0x04e45aaf; // exactInputSingle(...)
    bytes4 constant SEL_EXACT_INPUT = 0xb858183f; // exactInput(...)
    bytes4 constant SEL_EXACT_OUTPUT_SINGLE = 0x5023b4df; // exactOutputSingle(...)
    bytes4 constant SEL_MULTICALL = 0xac9650d8; // multicall(bytes[])

    // Pack IDs
    bytes32 constant PACK_LENDING = keccak256("LENDING");
    bytes32 constant PACK_V3_SWAP = keccak256("V3_SWAP");

    function run() external {
        vm.startBroadcast();

        // ═══════════════════════════════════════════════════════
        //  STEP 1: Deploy DeFiGuardPolicyV2
        // ═══════════════════════════════════════════════════════

        DeFiGuardPolicyV2 v2 = new DeFiGuardPolicyV2(GUARD, NFA);
        console.log("[1/8] DeFiGuardPolicyV2 deployed:", address(v2));

        // ═══════════════════════════════════════════════════════
        //  STEP 2: Approve in PolicyGuardV4
        // ═══════════════════════════════════════════════════════

        PolicyGuardV4(GUARD).approvePolicyContract(address(v2));
        console.log("[2/8] Approved in PolicyGuardV4");

        // ═══════════════════════════════════════════════════════
        //  STEP 3: Remove old DeFiGuardPolicy from template
        // ═══════════════════════════════════════════════════════

        PolicyGuardV4(GUARD).removeTemplatePolicy(
            TEMPLATE_LLM,
            DEFI_GUARD_INDEX
        );
        console.log("[3/8] Removed old DeFiGuard from template");

        // ═══════════════════════════════════════════════════════
        //  STEP 4: Add V2 to template
        // ═══════════════════════════════════════════════════════

        PolicyGuardV4(GUARD).addTemplatePolicy(TEMPLATE_LLM, address(v2));
        console.log("[4/8] Added V2 to template");

        // ═══════════════════════════════════════════════════════
        //  STEP 5: Configure global targets + V3 SmartRouter
        // ═══════════════════════════════════════════════════════

        v2.addGlobalTarget(PANCAKE_V2_ROUTER);
        v2.addGlobalTarget(WBNB);
        v2.addGlobalTarget(USDT);
        v2.addGlobalTarget(PANCAKE_V3_SMART_ROUTER);
        console.log("[5/8] 4 global targets: PancakeV2, WBNB, USDT, PancakeV3");

        // ═══════════════════════════════════════════════════════
        //  STEP 6: Configure global selectors (same as V1)
        // ═══════════════════════════════════════════════════════

        v2.addSelector(SEL_APPROVE);
        v2.addSelector(SEL_DECREASE_ALLOWANCE);
        v2.addSelector(SEL_SWAP_EXACT_TOKENS);
        v2.addSelector(SEL_SWAP_TOKENS_EXACT);
        v2.addSelector(SEL_SWAP_EXACT_ETH);
        v2.addSelector(SEL_SWAP_TOKENS_EXACT_ETH);
        v2.addSelector(SEL_SWAP_EXACT_TOKENS_ETH);
        v2.addSelector(SEL_SWAP_EXACT_TOKENS_FEE);
        v2.addSelector(SEL_SWAP_EXACT_ETH_FEE);
        v2.addSelector(SEL_WBNB_DEPOSIT);
        v2.addSelector(SEL_WBNB_WITHDRAW);
        console.log("[6/8] 11 global selectors configured");

        // ═══════════════════════════════════════════════════════
        //  STEP 7: Create LENDING pack
        // ═══════════════════════════════════════════════════════

        bytes4[] memory lendingSelectors = new bytes4[](6);
        lendingSelectors[0] = SEL_MINT;
        lendingSelectors[1] = SEL_MINT_BNB;
        lendingSelectors[2] = SEL_REDEEM;
        lendingSelectors[3] = SEL_REDEEM_UNDERLYING;
        lendingSelectors[4] = SEL_BORROW;
        lendingSelectors[5] = SEL_REPAY_BORROW;

        address[] memory lendingTargets = new address[](4);
        lendingTargets[0] = VENUS_VBNB;
        lendingTargets[1] = VENUS_VUSDT;
        lendingTargets[2] = VENUS_VUSDC;
        lendingTargets[3] = VENUS_VBUSD;

        v2.createPack(PACK_LENDING, lendingSelectors, lendingTargets, true);
        console.log(
            "[7/8] LENDING pack: 6 selectors + 4 Venus targets (renter-configurable)"
        );

        // ═══════════════════════════════════════════════════════
        //  STEP 8: Create V3_SWAP pack
        // ═══════════════════════════════════════════════════════

        bytes4[] memory v3Selectors = new bytes4[](4);
        v3Selectors[0] = SEL_EXACT_INPUT_SINGLE;
        v3Selectors[1] = SEL_EXACT_INPUT;
        v3Selectors[2] = SEL_EXACT_OUTPUT_SINGLE;
        v3Selectors[3] = SEL_MULTICALL;

        address[] memory v3Targets = new address[](0);
        // V3 SmartRouter is already in global whitelist (step 5)

        v2.createPack(PACK_V3_SWAP, v3Selectors, v3Targets, true);
        console.log("[8/8] V3_SWAP pack: 4 selectors (renter-configurable)");

        vm.stopBroadcast();

        // ═══════════════════════════════════════════════════════
        //  SUMMARY
        // ═══════════════════════════════════════════════════════

        console.log("");
        console.log("========== DEFI GUARD V2 DEPLOYMENT COMPLETE ==========");
        console.log("");
        console.log("  Contract      :", address(v2));
        console.log("  Global Targets: 4 (PancakeV2, WBNB, USDT, PancakeV3)");
        console.log("  Global Sels   : 11 (swap + approve + wrap)");
        console.log("  Pack LENDING  : 6 sels + 4 Venus vTokens");
        console.log("  Pack V3_SWAP  : 4 sels (router in global)");
        console.log("");
        console.log("Renters can now call:");
        console.log("  enablePack(tokenId, PACK_LENDING)  to use Venus");
        console.log("  enablePack(tokenId, PACK_V3_SWAP)  to use PancakeV3");
        console.log("");
        console.log("Update .env:");
        console.log("  DEFI_GUARD=", address(v2));
        console.log("======================================================");
    }
}
