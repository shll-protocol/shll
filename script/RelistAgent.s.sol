// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AgentNFA} from "../src/AgentNFA.sol";
import {ListingManager} from "../src/ListingManager.sol";
import {TokenWhitelistPolicy} from "../src/policies/TokenWhitelistPolicy.sol";
import {DexWhitelistPolicy} from "../src/policies/DexWhitelistPolicy.sol";
import {CooldownPolicy} from "../src/policies/CooldownPolicy.sol";
import {IBAP578} from "../src/interfaces/IBAP578.sol";

/// @title RelistAgent — Cancel old listing, mint new agent, relist
contract RelistAgent is Script {
    function run() external {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", uint256(0));
        address router = vm.envAddress("ROUTER_ADDRESS");
        address usdt = vm.envAddress("USDT_ADDRESS");
        address wbnb = vm.envAddress("WBNB_ADDRESS");

        AgentNFA nfa = AgentNFA(vm.envAddress("AGENT_NFA"));
        ListingManager lm = ListingManager(payable(vm.envAddress("LISTING_MANAGER")));
        TokenWhitelistPolicy tokenWL = TokenWhitelistPolicy(vm.envAddress("TOKEN_WL"));
        DexWhitelistPolicy dexWL = DexWhitelistPolicy(vm.envAddress("DEX_WL"));
        CooldownPolicy cooldown = CooldownPolicy(vm.envAddress("COOLDOWN"));

        bytes32 TEMPLATE_KEY = keccak256("llm_trader_v3");

        // Old listing ID (tokenId 0)
        bytes32 oldListingId = lm.getListingId(address(nfa), 0);

        console.log("========================================");
        console.log("  Relist Agent - Cancel + Mint + List");
        console.log("========================================");
        console.log("Old listing ID:");
        console.logBytes32(oldListingId);
        console.log("Start block:", block.number);

        if (deployerKey != 0) {
            vm.startBroadcast(deployerKey);
        } else {
            vm.startBroadcast();
        }

        // 1. Cancel old listing
        lm.cancelListing(oldListingId);
        console.log("[1] Old listing canceled");

        // 2. Mint new agent
        IBAP578.AgentMetadata memory meta = IBAP578.AgentMetadata({
            persona: '{"name":"LLM Trader Agent V2","description":"AI-powered autonomous trading agent - post audit"}',
            experience: "Template",
            voiceHash: "",
            animationURI: "",
            vaultURI: "",
            vaultHash: bytes32(0)
        });

        uint256 newTokenId = nfa.mintAgent(
            nfa.owner(),
            bytes32(uint256(1)),
            nfa.TYPE_LLM_TRADER(),
            "https://api.shll.run/api/metadata/1",
            meta
        );
        console.log("[2] New agent minted, tokenId:", newTokenId);

        // 3. Register as template (reuse same key)
        nfa.registerTemplate(newTokenId, TEMPLATE_KEY);
        console.log("[3] Registered as template: llm_trader_v3");

        // 4. Configure per-template whitelist
        tokenWL.addToken(newTokenId, usdt);
        tokenWL.addToken(newTokenId, wbnb);
        console.log("[4] Token whitelist: USDT, WBNB");

        dexWL.addDex(newTokenId, router);
        console.log("[5] DEX whitelist: Router");

        cooldown.setCooldown(newTokenId, 60);
        console.log("[6] Cooldown: 60s");

        // 5. Create new listing
        bytes32 newListingId = lm.createTemplateListing(
            address(nfa),
            newTokenId,
            uint96(0.005 ether),
            1
        );
        console.log("[7] New listing created at 0.005 BNB/day");
        console.log("New listing ID:");
        console.logBytes32(newListingId);
        console.log("New tokenId:", newTokenId);
        console.log("Block:", block.number);

        vm.stopBroadcast();

        console.log("");
        console.log("========================================");
        console.log("  DONE - Update indexer START_BLOCK to:");
        console.log("  ", block.number);
        console.log("========================================");
    }
}
