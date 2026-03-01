// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AgentNFA} from "../src/AgentNFA.sol";
import {ListingManagerV2} from "../src/ListingManagerV2.sol";
import {PolicyGuardV4} from "../src/PolicyGuardV4.sol";
import {IBAP578} from "../src/interfaces/IBAP578.sol";

/// @title RegisterLLMTemplateMainnet — Deploy free LLM Trader on BSC Mainnet
/// @notice 4 policies: ReceiverGuard + SpendingLimitV2 + Cooldown + DeFiGuardV2
/// @dev Usage:
///      cp .env.mainnet .env
///      forge script script/RegisterLLMTemplateMainnet.s.sol \
///        --rpc-url $RPC_URL --account deployer --broadcast --gas-price 3000000000 -vvv
contract RegisterLLMTemplateMainnet is Script {
    bytes32 constant TEMPLATE_KEY = keccak256("llm_trader_v4_free");

    function run() external {
        // ── Read env ──
        address nfaAddr = vm.envAddress("AGENT_NFA");
        address guardAddr = vm.envAddress("POLICY_GUARD_V4");
        address lmV2Addr = vm.envAddress("LISTING_MANAGER_V2");

        // Policies (V2)
        address spendingLimitV2 = vm.envAddress("SPENDING_LIMIT_V2");
        address cooldown = vm.envAddress("COOLDOWN");
        address receiverGuard = vm.envAddress("RECEIVER_GUARD");
        address defiGuardV2 = vm.envAddress("DEFI_GUARD_V2");

        // Tokens
        address usdt = vm.envAddress("USDT_ADDRESS");
        address wbnb = vm.envAddress("WBNB_ADDRESS");
        address usdc = vm.envAddress("USDC_ADDRESS");
        address eth = vm.envAddress("ETH_ADDRESS");
        address btcb = vm.envAddress("BTCB_ADDRESS");

        // Contracts
        AgentNFA nfa = AgentNFA(nfaAddr);
        PolicyGuardV4 guard = PolicyGuardV4(guardAddr);
        ListingManagerV2 lm = ListingManagerV2(lmV2Addr);

        address deployer = nfa.owner();

        console.log("========================================================");
        console.log("  Register LLM Trader Template (Mainnet, FREE)");
        console.log("========================================================");
        console.log("Deployer:         ", deployer);
        console.log("AgentNFA:         ", nfaAddr);
        console.log("PolicyGuardV4:    ", guardAddr);
        console.log("ListingManagerV2: ", lmV2Addr);
        console.log("");

        vm.startBroadcast();

        // ═══════ 1. Mint LLM Template Agent ═══════
        IBAP578.AgentMetadata memory meta = IBAP578.AgentMetadata({
            persona: '{"name":"LLM Trader Agent","description":"AI-powered autonomous trading agent driven by LLM reasoning. Supports swap, lending, and multi-DEX operations on BNB Chain."}',
            experience: "Template",
            voiceHash: "",
            animationURI: "",
            vaultURI: "",
            vaultHash: bytes32(0)
        });

        uint256 tokenId = nfa.mintAgent(
            deployer,
            bytes32(uint256(2)), // policyId placeholder
            nfa.TYPE_LLM_TRADER(),
            "https://shll.run/api/metadata/1",
            meta
        );
        console.log("  [1] mint      tokenId:", tokenId);

        // ═══════ 2. Register as template ═══════
        nfa.registerTemplate(tokenId, TEMPLATE_KEY);
        console.log("  [2] register  template: llm_trader_v4_free");

        // ═══════ 3. Attach 4 policies ═══════
        guard.addTemplatePolicy(TEMPLATE_KEY, receiverGuard);
        console.log("  [3a] policy   ReceiverGuardPolicy");

        guard.addTemplatePolicy(TEMPLATE_KEY, spendingLimitV2);
        console.log("  [3b] policy   SpendingLimitPolicyV2");

        guard.addTemplatePolicy(TEMPLATE_KEY, cooldown);
        console.log("  [3c] policy   CooldownPolicy");

        guard.addTemplatePolicy(TEMPLATE_KEY, defiGuardV2);
        console.log("  [3d] policy   DeFiGuardPolicyV2");

        // ═══════ 4. Configure SpendingLimitV2 ═══════
        // Interface: setTemplateCeiling(templateId, maxPerTx, maxPerDay, maxSlippageBps)
        ISpendingLimitV2(spendingLimitV2).setTemplateCeiling(
            TEMPLATE_KEY,
            10 ether, // 10 BNB per tx
            50 ether, // 50 BNB per day
            500 // 5% slippage
        );
        console.log("  [4a] ceiling  10 BNB/tx, 50 BNB/day, 5% slippage");

        // Approve ceiling: 100 BNB worth of token approvals
        ISpendingLimitV2(spendingLimitV2).setTemplateApproveCeiling(
            TEMPLATE_KEY,
            100 ether
        );
        console.log("  [4b] approve  ceiling 100 BNB");

        // Token whitelist: USDT, WBNB, USDC, ETH, BTCB
        ISpendingLimitV2(spendingLimitV2).setTemplateTokenRestriction(
            TEMPLATE_KEY,
            true
        );
        ISpendingLimitV2(spendingLimitV2).addTemplateToken(TEMPLATE_KEY, usdt);
        ISpendingLimitV2(spendingLimitV2).addTemplateToken(TEMPLATE_KEY, wbnb);
        ISpendingLimitV2(spendingLimitV2).addTemplateToken(TEMPLATE_KEY, usdc);
        ISpendingLimitV2(spendingLimitV2).addTemplateToken(TEMPLATE_KEY, eth);
        ISpendingLimitV2(spendingLimitV2).addTemplateToken(TEMPLATE_KEY, btcb);
        console.log("  [4c] tokens   USDT, WBNB, USDC, ETH, BTCB");

        // ═══════ 5. Configure Cooldown ═══════
        ICooldown(cooldown).setCooldown(tokenId, 60);
        console.log("  [5] cooldown  60 seconds");

        // ═══════ 6. Approve + List (FREE — pricePerDay = 0) ═══════
        nfa.approve(address(lm), tokenId);
        bytes32 listingId = lm.createTemplateListing(
            address(nfa),
            tokenId,
            0, // FREE
            1 // min 1 day
        );
        console.log("  [6] listing   FREE, minDays=1");
        console.log("  [6] listingId:");
        console.logBytes32(listingId);

        vm.stopBroadcast();

        console.log("");
        console.log("========================================================");
        console.log("  LLM TEMPLATE REGISTERED SUCCESSFULLY");
        console.log("  Token ID:  ", tokenId);
        console.log("  Price:      FREE (0 BNB/day)");
        console.log("  Policies:   4 (ReceiverGuard, SpendingLimitV2,");
        console.log("               Cooldown, DeFiGuardV2)");
        console.log("  Tokens:     USDT, WBNB, USDC, ETH, BTCB");
        console.log("========================================================");
    }
}

// Minimal interfaces to avoid full imports
interface ISpendingLimitV2 {
    function setTemplateCeiling(
        bytes32 templateId,
        uint256 maxPerTx,
        uint256 maxPerDay,
        uint256 maxSlippageBps
    ) external;
    function setTemplateApproveCeiling(
        bytes32 templateId,
        uint256 maxApproveAmount
    ) external;
    function setTemplateTokenRestriction(
        bytes32 templateId,
        bool enabled
    ) external;
    function addTemplateToken(bytes32 templateId, address token) external;
}

interface ICooldown {
    function setCooldown(uint256 tokenId, uint256 seconds_) external;
}
