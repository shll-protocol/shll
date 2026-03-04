// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ProtocolRegistry} from "../src/ProtocolRegistry.sol";

/// @title Register4Protocols — Minimal script with no view calls (avoids BSC RPC fork issue)
/// @dev Since registerProtocol() internally calls policy view functions, we CANNOT avoid
///      forge fork-backend. Instead, this script makes only on-chain calls.
///      Use: forge script ... --broadcast --skip-simulation --gas-limit 2000000
contract Register4Protocols is Script {
    address constant REGISTRY = 0x1A5EA54a3beaf4fba75f73581cf6A945746E6DF1;

    function run() external {
        vm.startBroadcast();
        ProtocolRegistry r = ProtocolRegistry(REGISTRY);

        _registerPancakeV2(r);
        _registerPancakeV3(r);
        _registerFourMeme(r);
        _registerVenus(r);

        vm.stopBroadcast();
    }

    function _registerPancakeV2(ProtocolRegistry r) internal {
        bytes4[] memory a = new bytes4[](9);
        a[0] = 0x38ed1739;
        a[1] = 0x8803dbee;
        a[2] = 0x7ff36ab5;
        a[3] = 0x4a25d94a;
        a[4] = 0x791ac947;
        a[5] = 0x5c11d795;
        a[6] = 0xb6f9de95;
        a[7] = 0xd0e30db0;
        a[8] = 0x2e1a7d4d;
        bytes4[] memory b = new bytes4[](0);
        address[] memory t = new address[](3);
        t[0] = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
        t[1] = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
        t[2] = 0x55d398326f99059fF775485246999027B3197955;
        r.registerProtocol(
            keccak256("PANCAKESWAP_V2"),
            ProtocolRegistry.ProtocolConfig("PancakeSwap V2", a, b, 0, t, false)
        );
    }

    function _registerPancakeV3(ProtocolRegistry r) internal {
        bytes4[] memory a = new bytes4[](2);
        a[0] = 0x04e45aaf;
        a[1] = 0xac9650d8;
        bytes4[] memory b = new bytes4[](0);
        address[] memory t = new address[](1);
        t[0] = 0x13f4EA83D0bd40E75C8222255bc855a974568Dd4;
        r.registerProtocol(
            keccak256("PANCAKESWAP_V3"),
            ProtocolRegistry.ProtocolConfig("PancakeSwap V3", a, b, 0, t, false)
        );
    }

    function _registerFourMeme(ProtocolRegistry r) internal {
        bytes4[] memory a = new bytes4[](5);
        a[0] = 0x3deec419;
        a[1] = 0xd55e62e4;
        a[2] = 0xcf084e38;
        a[3] = 0x2d296bf1;
        a[4] = 0xe8e93f56;
        bytes4[] memory b = new bytes4[](3);
        b[0] = 0x3deec419;
        b[1] = 0xcf084e38;
        b[2] = 0x2d296bf1;
        address[] memory t = new address[](3);
        t[0] = 0x5c952063c7fc8610FFDB798152D69F0B9550762b;
        t[1] = 0x38b2bF01168b0dbf0C4274BecBa0c572aECfADF1;
        t[2] = 0x10E42362e5dd7e0aF97D99256150dC08D1Ec367d;
        r.registerProtocol(
            keccak256("FOUR_MEME"),
            ProtocolRegistry.ProtocolConfig("Four.meme", a, b, 5, t, false)
        );
    }

    function _registerVenus(ProtocolRegistry r) internal {
        bytes4[] memory a = new bytes4[](6);
        a[0] = 0xa0712d68;
        a[1] = 0x1249c58b;
        a[2] = 0xdb006a75;
        a[3] = 0x852a12e3;
        a[4] = 0xc5ebeaec;
        a[5] = 0x0e752702;
        bytes4[] memory b = new bytes4[](0);
        address[] memory t = new address[](4);
        t[0] = 0xA07c5b74C9B40447a954e1466938b865b6BBea36;
        t[1] = 0xfD5840Cd36d94D7229439859C0112a4185BC0255;
        t[2] = 0xecA88125a5ADbe82614ffC12D0DB554E2e2867C8;
        t[3] = 0x95c78222B3D6e262426483D42CfA53685A67Ab9D;
        r.registerProtocol(
            keccak256("VENUS"),
            ProtocolRegistry.ProtocolConfig("Venus Protocol", a, b, 0, t, false)
        );
    }
}
