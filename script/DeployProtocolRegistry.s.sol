// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ProtocolRegistry} from "../src/ProtocolRegistry.sol";
import {PolicyGuardV4} from "../src/PolicyGuardV4.sol";

/// @title DeployProtocolRegistry — Deploy + pre-register protocols + transfer ownership
/// @notice Steps:
///   1. Deploy ProtocolRegistry
///   2. Pre-register PancakeSwap V2, PancakeSwap V3, Four.meme
///   3. Transfer PolicyGuardV4 ownership to Registry (Ownable2Step)
///   4. Accept ownership from Registry
///
/// @dev Usage:
///   forge script script/DeployProtocolRegistry.s.sol \
///     --account deployer --rpc-url https://bsc-dataseed1.binance.org \
///     --broadcast --gas-price 3000000000 --skip-simulation -vvv
///
/// Required env vars:
///   POLICY_GUARD_V4          — PolicyGuardV4 address
///   RECEIVER_GUARD_V2        — ReceiverGuardPolicyV2 address
///   DEFI_GUARD_V2            — DeFiGuardPolicyV2 address
///   SPENDING_LIMIT_V2        — SpendingLimitPolicyV2 address
contract DeployProtocolRegistry is Script {
    // ═══════════════════════════════════════════════════════
    //           BSC Mainnet Policy Addresses (defaults)
    // ═══════════════════════════════════════════════════════

    address constant DEFAULT_POLICY_GUARD =
        0x25d17eA0e3Bcb8CA08a2BFE917E817AFc05dbBB3;
    address constant DEFAULT_RECEIVER_GUARD =
        0x7358D950599bd27E0Ac677B54563F71403665f92;
    address constant DEFAULT_DEFI_GUARD =
        0xB248AF39b849fB10c271f13220c86be4cb56eD0e;
    address constant DEFAULT_SPENDING_LIMIT =
        0xd942dEe00d65c8012E39037a7a77Bc50645e5338;

    // ═══════════════════════════════════════════════════════
    //              PROTOCOL CONFIGURATIONS
    // ═══════════════════════════════════════════════════════

    function _pancakeSwapV2()
        internal
        pure
        returns (ProtocolRegistry.ProtocolConfig memory)
    {
        // All selectors for DeFiGuard global whitelist
        bytes4[] memory allSels = new bytes4[](9);
        allSels[0] = 0x38ed1739; // swapExactTokensForTokens
        allSels[1] = 0x8803dbee; // swapTokensForExactTokens
        allSels[2] = 0x4a25d94a; // swapTokensForExactETH
        allSels[3] = 0x7ff36ab5; // swapExactETHForTokens
        allSels[4] = 0xb6f9de95; // swapExactETHForTokensSupportingFeeOnTransferTokens
        allSels[5] = 0x791ac947; // swapExactTokensForETHSupportingFeeOnTransferTokens
        allSels[6] = 0x5c11d795; // swapExactTokensForTokensSupportingFeeOnTransferTokens
        allSels[7] = 0x095ea7b3; // approve
        allSels[8] = 0xd0e30db0; // WBNB deposit

        // Buy selectors: already hardcoded in ReceiverGuardV2 constructor
        bytes4[] memory buySels = new bytes4[](0);

        // Targets
        address[] memory targets = new address[](2);
        targets[0] = 0x10ED43C718714eb63d5aA57B78B54704E256024E; // PancakeRouter V2
        targets[1] = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c; // WBNB

        return
            ProtocolRegistry.ProtocolConfig({
                name: "PancakeSwap V2",
                allSelectors: allSels,
                buySelectors: buySels,
                receiverPattern: 0, // already set in constructor
                targets: targets,
                active: false
            });
    }

    function _pancakeSwapV3()
        internal
        pure
        returns (ProtocolRegistry.ProtocolConfig memory)
    {
        bytes4[] memory allSels = new bytes4[](2);
        allSels[0] = 0x04e45aaf; // exactInputSingle
        allSels[1] = 0xa457c2d7; // decreaseAllowance

        // Buy selectors: exactInputSingle already in constructor
        bytes4[] memory buySels = new bytes4[](0);

        address[] memory targets = new address[](1);
        targets[0] = 0x13f4EA83D0bd40E75C8222255bc855a974568Dd4; // V3 Smart Router

        return
            ProtocolRegistry.ProtocolConfig({
                name: "PancakeSwap V3",
                allSelectors: allSels,
                buySelectors: buySels,
                receiverPattern: 0,
                targets: targets,
                active: false
            });
    }

    function _fourMeme()
        internal
        pure
        returns (ProtocolRegistry.ProtocolConfig memory)
    {
        bytes4[] memory allSels = new bytes4[](5);
        allSels[0] = 0x3deec419; // purchaseTokenAMAP (V1 buy)
        allSels[1] = 0x9b911b5e; // saleToken (V1 sell)
        allSels[2] = 0x87f27655; // buyTokenAMAP (V2 buy)
        allSels[3] = 0xf464e7db; // sellToken (V2 sell)
        allSels[4] = 0x02ff2dcc; // buyToken (X Mode buy)

        bytes4[] memory buySels = new bytes4[](3);
        buySels[0] = 0x3deec419; // purchaseTokenAMAP
        buySels[1] = 0x87f27655; // buyTokenAMAP
        buySels[2] = 0x02ff2dcc; // buyToken (X Mode)

        address[] memory targets = new address[](3);
        targets[0] = 0xEC4549caDcE5DA21Df6E6422d448034B5233bFbC; // TokenManagerV1
        targets[1] = 0x5c952063c7fc8610FFDB798152D69F0B9550762b; // TokenManagerV2
        targets[2] = 0xF251F83e40a78868FcfA3FA4599Dad6494E46034; // HelperV3

        return
            ProtocolRegistry.ProtocolConfig({
                name: "Four.meme",
                allSelectors: allSels,
                buySelectors: buySels,
                receiverPattern: 5, // pass-through
                targets: targets,
                active: false
            });
    }

    function _venus()
        internal
        pure
        returns (ProtocolRegistry.ProtocolConfig memory)
    {
        // Venus lending selectors
        bytes4[] memory allSels = new bytes4[](6);
        allSels[0] = 0xa0712d68; // mint(uint256)
        allSels[1] = 0x1249c58b; // mint() payable (vBNB)
        allSels[2] = 0xdb006a75; // redeem(uint256)
        allSels[3] = 0x852a12e3; // redeemUnderlying(uint256)
        allSels[4] = 0xc5ebeaec; // borrow(uint256)
        allSels[5] = 0x0e752702; // repayBorrow(uint256)

        // No buy selectors (lending, not swap)
        bytes4[] memory buySels = new bytes4[](0);

        // Venus vToken contracts
        address[] memory targets = new address[](4);
        targets[0] = 0xA07c5b74C9B40447a954e1466938b865b6BBea36; // vBNB
        targets[1] = 0xfD5840Cd36d94D7229439859C0112a4185BC0255; // vUSDT
        targets[2] = 0xecA88125a5ADbe82614ffC12D0DB554E2e2867C8; // vUSDC
        targets[3] = 0x95c78222B3D6e262426483D42CfA53685A67Ab9D; // vBUSD

        return
            ProtocolRegistry.ProtocolConfig({
                name: "Venus Protocol",
                allSelectors: allSels,
                buySelectors: buySels,
                receiverPattern: 0, // no buy operations
                targets: targets,
                active: false
            });
    }

    // ═══════════════════════════════════════════════════════
    //                    EXECUTION
    // ═══════════════════════════════════════════════════════

    function run() external {
        // Read addresses (fall back to defaults)
        address guardAddr = vm.envOr("POLICY_GUARD_V4", DEFAULT_POLICY_GUARD);
        address rgAddr = vm.envOr("RECEIVER_GUARD_V2", DEFAULT_RECEIVER_GUARD);
        address dgAddr = vm.envOr("DEFI_GUARD_V2", DEFAULT_DEFI_GUARD);
        address slAddr = vm.envOr("SPENDING_LIMIT_V2", DEFAULT_SPENDING_LIMIT);

        PolicyGuardV4 guard = PolicyGuardV4(guardAddr);

        vm.startBroadcast();

        // ── STEP 1: Deploy ProtocolRegistry ──
        // NOTE: On-chain transferOwnership() will revert if broadcaster != guard.owner()
        ProtocolRegistry registry = new ProtocolRegistry(
            rgAddr,
            dgAddr,
            slAddr,
            guardAddr
        );
        console.log("ProtocolRegistry deployed at:", address(registry));

        // ── STEP 2: Transfer PolicyGuardV4 ownership → Registry ──
        guard.transferOwnership(address(registry));
        console.log("Ownership transfer initiated (pending acceptance)");

        // ── STEP 3: Accept ownership from Registry ──
        registry.acceptGuardOwnership();
        console.log("Registry accepted PolicyGuardV4 ownership");

        // Verify ownership
        require(guard.owner() == address(registry), "Guard owner mismatch");
        console.log("Verified: PolicyGuardV4.owner() = Registry");

        // ── STEP 4: Register protocols via Registry ──
        registry.registerProtocol(
            keccak256("PANCAKESWAP_V2"),
            _pancakeSwapV2()
        );
        console.log("  Registered: PancakeSwap V2");

        registry.registerProtocol(
            keccak256("PANCAKESWAP_V3"),
            _pancakeSwapV3()
        );
        console.log("  Registered: PancakeSwap V3");

        registry.registerProtocol(keccak256("FOUR_MEME"), _fourMeme());
        console.log("  Registered: Four.meme");

        registry.registerProtocol(keccak256("VENUS"), _venus());
        console.log("  Registered: Venus Protocol");

        vm.stopBroadcast();

        // ── SUMMARY ──
        console.log("");
        console.log("============ PROTOCOL REGISTRY DEPLOYED ============");
        console.log("");
        console.log("  Registry     :", address(registry));
        console.log("  Guard (owned):", guardAddr);
        console.log("  ReceiverGuard:", rgAddr);
        console.log("  DeFiGuard    :", dgAddr);
        console.log("  SpendingLimit:", slAddr);
        console.log("");
        console.log("  Protocols registered: 4");
        console.log("    - PancakeSwap V2");
        console.log("    - PancakeSwap V3");
        console.log("    - Four.meme");
        console.log("    - Venus Protocol");
        console.log("");
        console.log("  Add to .env:");
        console.log("    PROTOCOL_REGISTRY=", address(registry));
        console.log("====================================================");
    }
}
