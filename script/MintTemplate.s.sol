// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AgentNFA} from "../src/AgentNFA.sol";
import {IBAP578} from "../src/interfaces/IBAP578.sol";

/// @title MintAndRegister — Mint + Register template in one shot
/// @notice ERC-8004 registration URI is embedded as base64 data URI.
///         Update AGENT_NFA env var after deploying new NFA.
contract MintAndRegister is Script {
    // ERC-8004 Agent Registration File (base64 encoded)
    // {
    //   "type": "https://eips.ethereum.org/EIPS/eip-8004#",
    //   "version": "1.0.0",
    //   "name": "SHLL DeFi Agent",
    //   "description": "AI-powered autonomous DeFi agent with on-chain safety enforcement via PolicyGuard.",
    //   "image": "https://shll.run/logo-highres.png",
    //   "url": "https://shll.run",
    //   "provider": "SHLL",
    //   "capabilities": ["defi_trading","portfolio_management","lending","risk_management","autonomous_execution"],
    //   "supportedChains": ["56"],
    //   "active": true,
    //   "x402Support": false,
    //   "supportedTrust": ["reputation"]
    // }
    string constant AGENT_URI =
        "data:application/json;base64,eyJ0eXBlIjoiaHR0cHM6Ly9laXBzLmV0aGVyZXVtLm9yZy9FSVBTL2VpcC04MDA0IyIsInZlcnNpb24iOiIxLjAuMCIsIm5hbWUiOiJTSExMIERlRmkgQWdlbnQiLCJkZXNjcmlwdGlvbiI6IkFJLXBvd2VyZWQgYXV0b25vbW91cyBEZUZpIGFnZW50IHdpdGggb24tY2hhaW4gc2FmZXR5IGVuZm9yY2VtZW50IHZpYSBQb2xpY3lHdWFyZC4gU3VwcG9ydHMgc3dhcCwgbGVuZGluZywgYW5kIHBvcnRmb2xpbyBtYW5hZ2VtZW50IG9uIEJOQiBDaGFpbi4iLCJpbWFnZSI6Imh0dHBzOi8vc2hsbC5ydW4vbG9nby1oaWdocmVzLnBuZyIsInVybCI6Imh0dHBzOi8vc2hsbC5ydW4iLCJwcm92aWRlciI6IlNITEwiLCJjYXBhYmlsaXRpZXMiOlsiZGVmaV90cmFkaW5nIiwicG9ydGZvbGlvX21hbmFnZW1lbnQiLCJsZW5kaW5nIiwicmlza19tYW5hZ2VtZW50IiwiYXV0b25vbW91c19leGVjdXRpb24iXSwic3VwcG9ydGVkQ2hhaW5zIjpbIjU2Il0sImFjdGl2ZSI6dHJ1ZSwieDQwMlN1cHBvcnQiOmZhbHNlLCJzdXBwb3J0ZWRUcnVzdCI6WyJyZXB1dGF0aW9uIl19";

    function run() external {
        address agentNFAAddr = vm.envAddress("AGENT_NFA");
        AgentNFA agentNFA = AgentNFA(agentNFAAddr);

        // Hardcode deployer EOA as recipient
        address deployer = 0x51eD50c9e29481dB812d004EC4322CCdFa9a2868;

        IBAP578.AgentMetadata memory meta = IBAP578.AgentMetadata({
            persona: '{"name":"SHLL DeFi Agent","description":"AI-powered autonomous DeFi agent with on-chain safety via PolicyGuard."}',
            experience: "Template",
            voiceHash: "",
            animationURI: "https://shll.run/logo-highres.png",
            vaultURI: "https://shll.run",
            vaultHash: bytes32(0)
        });

        vm.startBroadcast();

        uint256 tokenId = agentNFA.mintAgent(
            deployer,
            bytes32(uint256(1)),
            keccak256("TYPE_LLM_TRADER"),
            AGENT_URI,
            meta
        );
        console.log("Minted tokenId:", tokenId);
        console.log("Vault:", agentNFA.accountOf(tokenId));
        console.log("ERC-8004 URI set to SHLL branded registration file");

        vm.stopBroadcast();
    }
}
