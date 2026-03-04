// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {DeFiGuardPolicyV2} from "../src/policies/DeFiGuardPolicyV2.sol";

/// @title CreateFourMemePack — Add Four.meme Launchpad support
/// @notice Creates a FOUR_MEME selector pack for DeFiGuardPolicyV2.
///         This pack allows SHLL agents to trade tokens on Four.meme's
///         internal bonding curve (buy/sell before DEX migration).
///
/// @dev Usage:
///   forge script script/CreateFourMemePack.s.sol \
///     --account deployer --rpc-url https://bsc-dataseed1.binance.org \
///     --broadcast --gas-price 3000000000 --skip-simulation -vvv
contract CreateFourMemePack is Script {
    // DeFiGuardPolicyV2 address on BSC Mainnet
    // NOTE: Update this to the actual deployed DeFiGuardPolicyV2 address
    address constant DEFI_GUARD_V2 = 0xB248AF39b849fB10c271f13220c86be4cb56eD0e;

    // ── Four.meme Contract Addresses (BSC Mainnet) ──
    address constant FOUR_TOKEN_MANAGER_V1 =
        0xEC4549caDcE5DA21Df6E6422d448034B5233bFbC;
    address constant FOUR_TOKEN_MANAGER_V2 =
        0x5c952063c7fc8610FFDB798152D69F0B9550762b;
    address constant FOUR_HELPER_V3 =
        0xF251F83e40a78868FcfA3FA4599Dad6494E46034;

    // ── Four.meme Function Selectors ──
    // TokenManager V1:
    //   purchaseTokenAMAP(address,uint256,uint256): 0x8185840e
    //   saleToken(address,uint256):                 0xd3e5b008
    // TokenManager V2:
    //   buyTokenAMAP(address,uint256,uint256):       0x97e8d17d
    //   sellToken(address,uint256):                  0x6c197ff5
    //   buyToken(bytes,uint256,bytes):               0x7fd6f15c  (X Mode)
    // TokenManagerHelper3:
    //   buyWithEth(uint256,address,address,uint256,uint256): 0x... (for ERC20 pairs)
    //   sellForEth(uint256,address,uint256,uint256,uint256,address): 0x...
    //
    // We include the most commonly used buy/sell selectors:
    bytes4 constant SEL_V1_PURCHASE_AMAP = 0x3deec419; // purchaseTokenAMAP(address,uint256,uint256)
    bytes4 constant SEL_V1_SALE = 0x9b911b5e; // saleToken(address,uint256)
    bytes4 constant SEL_V2_BUY_AMAP = 0x87f27655; // buyTokenAMAP(address,uint256,uint256)
    bytes4 constant SEL_V2_SELL = 0xf464e7db; // sellToken(address,uint256)
    bytes4 constant SEL_V2_BUY_XMODE = 0x02ff2dcc; // buyToken(bytes,uint256,bytes) - X Mode

    // Pack ID
    bytes32 constant PACK_FOUR_MEME = keccak256("FOUR_MEME");

    function run() external {
        vm.startBroadcast();

        DeFiGuardPolicyV2 v2 = DeFiGuardPolicyV2(DEFI_GUARD_V2);

        // ── Create FOUR_MEME pack ──
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = SEL_V1_PURCHASE_AMAP;
        selectors[1] = SEL_V1_SALE;
        selectors[2] = SEL_V2_BUY_AMAP;
        selectors[3] = SEL_V2_SELL;
        selectors[4] = SEL_V2_BUY_XMODE;

        address[] memory targets = new address[](3);
        targets[0] = FOUR_TOKEN_MANAGER_V1;
        targets[1] = FOUR_TOKEN_MANAGER_V2;
        targets[2] = FOUR_HELPER_V3;

        v2.createPack(PACK_FOUR_MEME, selectors, targets, true);

        vm.stopBroadcast();

        console.log("");
        console.log("========== FOUR.MEME PACK CREATED ==========");
        console.log("");
        console.log("  Pack ID       : FOUR_MEME");
        console.log("  Selectors     : 5 (V1 buy/sell + V2 buy/sell + X Mode)");
        console.log("  Targets       : 3 (TokenManager V1, V2, Helper V3)");
        console.log("  Configurable  : true (renters can toggle)");
        console.log("");
        console.log("Renters can now call:");
        console.log(
            "  enablePack(tokenId, keccak256('FOUR_MEME'))  to trade on Four.meme"
        );
        console.log("================================================");
    }
}
