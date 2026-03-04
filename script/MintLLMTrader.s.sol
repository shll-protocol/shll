// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AgentNFA} from "../src/AgentNFA.sol";
import {IBAP578} from "../src/interfaces/IBAP578.sol";

/// @title MintLLMTrader — STEP 1: Mint only (high gas)
contract MintLLMTrader is Script {
    AgentNFA constant NFA =
        AgentNFA(0xfFbf69F6FdE7710E4298C7dF7B03A35136fA15B3);
    address constant DEPLOYER = 0x51eD50c9e29481dB812d004EC4322CCdFa9a2868;

    bytes32 constant AGENT_TYPE =
        0xf03a8666449c9c4b8d4441d97da812c3ac61312ec971e34d97c6cc4ecd34eaa8; // keccak256("llm_trader")
    bytes32 constant TEMPLATE_KEY =
        0x3dc46d5bd1f9688714321cb4ca345d8fceda62126b3a9e58d22bdba4c967300f; // keccak256("llm_trader_v3")

    function run() external {
        IBAP578.AgentMetadata memory meta = IBAP578.AgentMetadata({
            persona: '{"name":"LLM Trader Agent","description":"AI-powered autonomous trading agent with contract-level safety.","manifest":{"riskLevel":"medium","version":"3.0.0","runnerMode":"llm","operationalMode":"managed"}}',
            experience: "Template",
            voiceHash: "",
            animationURI: "https://api.shll.run/logo-highres.png",
            vaultURI: "https://shll.run",
            vaultHash: bytes32(0)
        });

        vm.startBroadcast();

        uint256 tokenId = NFA.mintAgent(
            DEPLOYER,
            TEMPLATE_KEY,
            AGENT_TYPE,
            "https://api.shll.run/api/metadata/llm_trader",
            meta
        );

        vm.stopBroadcast();

        console.log("Minted tokenId:", tokenId);
        console.log("Vault:", NFA.accountOf(tokenId));
        console.log(
            "Next: cast send NFA registerTemplate(uint256,bytes32)",
            tokenId
        );
    }
}
