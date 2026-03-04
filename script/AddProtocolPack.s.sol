// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";

/// @title AddProtocolPack — One-shot protocol registration across all policies
/// @notice Registers a new DeFi protocol (selectors + targets) across:
///   1. ReceiverGuardPolicyV2  → setPatternBatch (buy selectors that carry BNB value)
///   2. DeFiGuardPolicyV2      → addSelector + addGlobalTarget
///   3. SpendingLimitPolicyV2  → setApprovedSpender (for approve/sell operations)
///
/// @dev Usage:
///   forge script script/AddProtocolPack.s.sol \
///     --account deployer --rpc-url https://bsc-dataseed1.binance.org \
///     --broadcast --gas-price 3000000000 --skip-simulation -vvv
///
///   To add a new protocol:
///   1. Copy the EXAMPLE section below
///   2. Fill in selectors, targets, and buy selectors
///   3. Run the script
contract AddProtocolPack is Script {
    // ═══════════════════════════════════════════════════════
    //               POLICY ADDRESSES (BSC Mainnet)
    // ═══════════════════════════════════════════════════════

    address constant RECEIVER_GUARD_V2 =
        0x7358D950599bd27E0Ac677B54563F71403665f92;
    address constant DEFI_GUARD_V2 = 0xB248AF39b849fB10c271f13220c86be4cb56eD0e;
    address constant SPENDING_LIMIT_V2 =
        0xd942dEe00d65c8012E39037a7a77Bc50645e5338;

    // ═══════════════════════════════════════════════════════
    //        PROTOCOL CONFIG — Edit this section
    // ═══════════════════════════════════════════════════════

    // Protocol name (for logging only)
    string constant PROTOCOL_NAME = "Four.meme";

    // ReceiverGuard pattern for buy selectors that carry msg.value
    //   5 = pass-through (no recipient extraction, token goes to msg.sender)
    //   1-4 = PancakeSwap patterns (see ReceiverGuardPolicyV2.sol)
    //   0 = skip registration (for selectors that don't carry value)
    uint8 constant RECEIVER_PATTERN = 5;

    function _buildConfig()
        internal
        pure
        returns (
            bytes4[] memory allSelectors,
            bytes4[] memory buySelectors,
            address[] memory targets
        )
    {
        // ── All selectors (DeFiGuard global whitelist) ──
        allSelectors = new bytes4[](5);
        allSelectors[0] = 0x3deec419; // purchaseTokenAMAP (V1 buy)
        allSelectors[1] = 0x9b911b5e; // saleToken (V1 sell)
        allSelectors[2] = 0x87f27655; // buyTokenAMAP (V2 buy)
        allSelectors[3] = 0xf464e7db; // sellToken (V2 sell)
        allSelectors[4] = 0x02ff2dcc; // buyToken (X Mode buy)

        // ── Buy selectors ONLY (ReceiverGuard — these carry msg.value) ──
        buySelectors = new bytes4[](3);
        buySelectors[0] = 0x3deec419; // purchaseTokenAMAP
        buySelectors[1] = 0x87f27655; // buyTokenAMAP
        buySelectors[2] = 0x02ff2dcc; // buyToken (X Mode)

        // ── Target contracts (DeFiGuard + SpendingLimit whitelist) ──
        targets = new address[](3);
        targets[0] = 0xEC4549caDcE5DA21Df6E6422d448034B5233bFbC; // TokenManagerV1
        targets[1] = 0x5c952063c7fc8610FFDB798152D69F0B9550762b; // TokenManagerV2
        targets[2] = 0xF251F83e40a78868FcfA3FA4599Dad6494E46034; // HelperV3
    }

    // ═══════════════════════════════════════════════════════
    //                    EXECUTION
    // ═══════════════════════════════════════════════════════

    function run() external {
        (
            bytes4[] memory allSelectors,
            bytes4[] memory buySelectors,
            address[] memory targets
        ) = _buildConfig();

        vm.startBroadcast();

        // ── 1. ReceiverGuardPolicyV2: register buy selectors ──
        if (buySelectors.length > 0 && RECEIVER_PATTERN > 0) {
            IReceiverGuardV2(RECEIVER_GUARD_V2).setPatternBatch(
                buySelectors,
                RECEIVER_PATTERN
            );
        }

        // ── 2. DeFiGuardPolicyV2: add selectors + targets to global whitelist ──
        IDeFiGuardV2 defiGuard = IDeFiGuardV2(DEFI_GUARD_V2);
        for (uint256 i = 0; i < allSelectors.length; i++) {
            // Skip if already added (avoid revert)
            if (!defiGuard.allowedSelectors(allSelectors[i])) {
                defiGuard.addSelector(allSelectors[i]);
            }
        }
        for (uint256 i = 0; i < targets.length; i++) {
            if (!defiGuard.globalAllowed(targets[i])) {
                defiGuard.addGlobalTarget(targets[i]);
            }
        }

        // ── 3. SpendingLimitPolicyV2: approve spenders ──
        ISpendingLimitV2 spendLimit = ISpendingLimitV2(SPENDING_LIMIT_V2);
        for (uint256 i = 0; i < targets.length; i++) {
            if (!spendLimit.approvedSpender(targets[i])) {
                spendLimit.setApprovedSpender(targets[i], true);
            }
        }

        vm.stopBroadcast();

        // ── Summary ──
        console.log("");
        console.log("============ PROTOCOL REGISTERED ============");
        console.log("");
        console.log("  Protocol      :", PROTOCOL_NAME);
        console.log("  Selectors     :", allSelectors.length);
        console.log("  Buy selectors :", buySelectors.length);
        console.log("  Targets       :", targets.length);
        console.log("  RG pattern    :", RECEIVER_PATTERN);
        console.log("");
        console.log("  Policies updated:");
        console.log("    [1] ReceiverGuardPolicyV2  - setPatternBatch");
        console.log(
            "    [2] DeFiGuardPolicyV2      - addSelector + addGlobalTarget"
        );
        console.log("    [3] SpendingLimitPolicyV2  - setApprovedSpender");
        console.log("=============================================");
    }
}

// ── Minimal interfaces ──

interface IReceiverGuardV2 {
    function setPatternBatch(
        bytes4[] calldata selectors,
        uint8 pattern
    ) external;
    function selectorPattern(bytes4) external view returns (uint8);
}

interface IDeFiGuardV2 {
    function addSelector(bytes4 selector) external;
    function addGlobalTarget(address target) external;
    function allowedSelectors(bytes4) external view returns (bool);
    function globalAllowed(address) external view returns (bool);
}

interface ISpendingLimitV2 {
    function setApprovedSpender(address spender, bool allowed) external;
    function approvedSpender(address) external view returns (bool);
}
