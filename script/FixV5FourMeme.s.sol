// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ProtocolRegistry} from "../src/ProtocolRegistry.sol";

/// @title FixV5FourMeme — Add missing Four.meme config to V5 Policies
/// @notice ProtocolRegistry was deployed pointing to old policies.
///         V5 policies (mutable agentNFA) were deployed later but never got
///         Four.meme selectors/targets registered.
///         This script uses emergencyCall() to fix all 3 V5 policies in one tx.
///
/// @dev Usage:
///   forge script script/FixV5FourMeme.s.sol \
///     --account deployer --rpc-url https://bsc-dataseed1.binance.org \
///     --broadcast --gas-price 3000000000 -vvv
contract FixV5FourMeme is Script {
    // ProtocolRegistry (owns PolicyGuardV4, can call V5 policy admin fns)
    address constant REGISTRY = 0x1A5EA54a3beaf4fba75f73581cf6A945746E6DF1;

    // V5 Policies
    address constant DEFI_GUARD_V5 = 0xD1b6a97400Bc62ed6000714E9810F36Fc1a251f1;
    address constant SPENDING_LIMIT_V5 =
        0x28efC8D513D44252EC26f710764ADe22b2569115;
    address constant RECEIVER_GUARD_V5 =
        0x7A9618ec6c2e9D93712326a7797A829895c0AfF6;

    // Four.meme targets
    address constant FOUR_TOKEN_MANAGER_V1 =
        0xEC4549caDcE5DA21Df6E6422d448034B5233bFbC;
    address constant FOUR_TOKEN_MANAGER_V2 =
        0x5c952063c7fc8610FFDB798152D69F0B9550762b;
    address constant FOUR_HELPER_V3 =
        0xF251F83e40a78868FcfA3FA4599Dad6494E46034;

    // Four.meme selectors
    bytes4 constant SEL_PURCHASE_TOKEN_AMAP = 0x3deec419; // V1 buy
    bytes4 constant SEL_SALE_TOKEN = 0x9b911b5e; // V1 sell
    bytes4 constant SEL_BUY_TOKEN_AMAP = 0x87f27655; // V2 buy
    bytes4 constant SEL_SELL_TOKEN = 0xf464e7db; // V2 sell
    bytes4 constant SEL_BUY_TOKEN = 0x02ff2dcc; // X Mode buy

    function run() external {
        ProtocolRegistry registry = ProtocolRegistry(REGISTRY);

        vm.startBroadcast();

        // ═════════════════════════════════════════════════════
        //  1. V5 DeFiGuard — Add 5 selectors
        // ═════════════════════════════════════════════════════
        console.log("=== V5 DeFiGuard: Adding Four.meme selectors ===");

        registry.emergencyCall(
            DEFI_GUARD_V5,
            abi.encodeWithSignature(
                "addSelector(bytes4)",
                SEL_PURCHASE_TOKEN_AMAP
            )
        );
        console.log("  + purchaseTokenAMAP (0x3deec419)");

        registry.emergencyCall(
            DEFI_GUARD_V5,
            abi.encodeWithSignature("addSelector(bytes4)", SEL_SALE_TOKEN)
        );
        console.log("  + saleToken (0x9b911b5e)");

        registry.emergencyCall(
            DEFI_GUARD_V5,
            abi.encodeWithSignature("addSelector(bytes4)", SEL_BUY_TOKEN_AMAP)
        );
        console.log("  + buyTokenAMAP (0x87f27655)");

        registry.emergencyCall(
            DEFI_GUARD_V5,
            abi.encodeWithSignature("addSelector(bytes4)", SEL_SELL_TOKEN)
        );
        console.log("  + sellToken (0xf464e7db)");

        registry.emergencyCall(
            DEFI_GUARD_V5,
            abi.encodeWithSignature("addSelector(bytes4)", SEL_BUY_TOKEN)
        );
        console.log("  + buyToken X Mode (0x02ff2dcc)");

        // ═════════════════════════════════════════════════════
        //  2. V5 DeFiGuard — Add 2 missing global targets
        // ═════════════════════════════════════════════════════
        console.log("=== V5 DeFiGuard: Adding Four.meme targets ===");

        registry.emergencyCall(
            DEFI_GUARD_V5,
            abi.encodeWithSignature(
                "addGlobalTarget(address)",
                FOUR_TOKEN_MANAGER_V1
            )
        );
        console.log("  + TokenManagerV1");

        registry.emergencyCall(
            DEFI_GUARD_V5,
            abi.encodeWithSignature("addGlobalTarget(address)", FOUR_HELPER_V3)
        );
        console.log("  + HelperV3");

        // ═════════════════════════════════════════════════════
        //  3. V5 SpendingLimit — Add 2 approved spenders
        // ═════════════════════════════════════════════════════
        console.log("=== V5 SpendingLimit: Adding Four.meme spenders ===");

        registry.emergencyCall(
            SPENDING_LIMIT_V5,
            abi.encodeWithSignature(
                "setApprovedSpender(address,bool)",
                FOUR_TOKEN_MANAGER_V1,
                true
            )
        );
        console.log("  + TokenManagerV1");

        registry.emergencyCall(
            SPENDING_LIMIT_V5,
            abi.encodeWithSignature(
                "setApprovedSpender(address,bool)",
                FOUR_HELPER_V3,
                true
            )
        );
        console.log("  + HelperV3");

        // ═════════════════════════════════════════════════════
        //  4. V5 ReceiverGuard — Set buy selector patterns (pattern=5, pass-through)
        // ═════════════════════════════════════════════════════
        console.log("=== V5 ReceiverGuard: Adding Four.meme buy patterns ===");

        bytes4[] memory buySelectors = new bytes4[](3);
        buySelectors[0] = SEL_PURCHASE_TOKEN_AMAP;
        buySelectors[1] = SEL_BUY_TOKEN_AMAP;
        buySelectors[2] = SEL_BUY_TOKEN;

        registry.emergencyCall(
            RECEIVER_GUARD_V5,
            abi.encodeWithSignature(
                "setPatternBatch(bytes4[],uint8)",
                buySelectors,
                uint8(5)
            )
        );
        console.log("  + 3 buy selectors with pattern=5 (pass-through)");

        vm.stopBroadcast();

        // ═════════════════════════════════════════════════════
        //  SUMMARY
        // ═════════════════════════════════════════════════════
        console.log("");
        console.log("============ FIX COMPLETE ============");
        console.log("  DeFiGuard V5:     5 selectors + 2 targets added");
        console.log("  SpendingLimit V5: 2 approved spenders added");
        console.log("  ReceiverGuard V5: 3 buy patterns set (pattern=5)");
        console.log("  Total emergencyCall: 10");
        console.log("======================================");
    }
}
