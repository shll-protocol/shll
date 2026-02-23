// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AgentNFA} from "../src/AgentNFA.sol";
import {ListingManager} from "../src/ListingManager.sol";
import {AgentNFAExtensions} from "../src/AgentNFAExtensions.sol";

import {PolicyGuardV4} from "../src/PolicyGuardV4.sol";
import {TokenWhitelistPolicy} from "../src/policies/TokenWhitelistPolicy.sol";
import {SpendingLimitPolicy} from "../src/policies/SpendingLimitPolicy.sol";
import {CooldownPolicy} from "../src/policies/CooldownPolicy.sol";
import {ReceiverGuardPolicy} from "../src/policies/ReceiverGuardPolicy.sol";
import {DexWhitelistPolicy} from "../src/policies/DexWhitelistPolicy.sol";
import {DeFiGuardPolicy} from "../src/policies/DeFiGuardPolicy.sol";
import {IBAP578} from "../src/interfaces/IBAP578.sol";

/// @title DeployV32PostAudit — Full Redeployment after EVMBench Security Audit
/// @notice Deploys 10 contracts + LLM template in 2 phases.
///   All contracts redeployed due to security fixes (10H/4M/1L):
///     - AgentNFA: setUser disabled, _mint, soulbound instances, commit fix, setPolicy fix
///     - PolicyGuardV4: zero-address checks
///     - ListingManager: agentNFA whitelist (V-001)
///     - SpendingLimitPolicy: increaseAllowance blocked, permit blocked, fail-close, exact-output swap fix
///     - ReceiverGuardPolicy: empty-calldata drain fix, value guard
///     - DexWhitelistPolicy: fail-close, spender extraction
///     - TokenWhitelistPolicy: fail-close
///     - CooldownPolicy: fail-close
///     - DeFiGuardPolicy: merged into main deploy (was separate before)
///
/// @dev Usage:
///   BSC Testnet:
///   forge script script/DeployV32PostAudit.s.sol \
///     --rpc-url $RPC_URL --broadcast --gas-price 5000000000 -vvv
///
///   BSC Mainnet:
///   forge script script/DeployV32PostAudit.s.sol \
///     --rpc-url $BSC_MAINNET_RPC --broadcast --gas-price 3000000000 \
///     --verify --etherscan-api-key $BSC_API_KEY -vvv
///
/// Required .env:
///   PRIVATE_KEY        — deployer private key (or use --account deployer)
///   ROUTER_ADDRESS     — PancakeSwap V2 Router
///   USDT_ADDRESS       — USDT token address
///   WBNB_ADDRESS       — WBNB token address
contract DeployV32PostAudit is Script {
    bytes32 constant TEMPLATE_LLM = keccak256("llm_trader_v3");

    // DeFi function selectors for DeFiGuardPolicy
    bytes4 constant SWAP_EXACT_TOKENS = 0x38ed1739;
    bytes4 constant SWAP_EXACT_ETH = 0x7ff36ab5;
    bytes4 constant SWAP_ETH_EXACT_TOKENS = 0xfb3bdb41;
    bytes4 constant SWAP_TOKENS_EXACT_ETH = 0x4a25d94a;
    bytes4 constant SWAP_EXACT_TOKENS_ETH = 0x18cbafe5;
    bytes4 constant APPROVE_SELECTOR = 0x095ea7b3;
    bytes4 constant TRANSFER_SELECTOR = 0xa9059cbb;
    bytes4 constant DEPOSIT_SELECTOR = 0xd0e30db0;
    bytes4 constant WITHDRAW_SELECTOR = 0x2e1a7d4d;

    // Deployed contract references
    PolicyGuardV4 guardV4;
    AgentNFA nfa;
    AgentNFAExtensions extensions;
    ListingManager lm;
    TokenWhitelistPolicy tokenWL;
    SpendingLimitPolicy spendingLimit;
    CooldownPolicy cooldown;
    ReceiverGuardPolicy receiverGuard;
    DexWhitelistPolicy dexWL;
    DeFiGuardPolicy defiGuard;

    function run() external {
        // Support both PRIVATE_KEY (.env) and --account keystore modes
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", uint256(0));
        address deployer = deployerKey != 0 ? vm.addr(deployerKey) : msg.sender;
        address router = vm.envAddress("ROUTER_ADDRESS");
        address usdt = vm.envAddress("USDT_ADDRESS");
        address wbnb = vm.envAddress("WBNB_ADDRESS");

        console.log("========================================================");
        console.log("  SHLL V3.2 Post-Audit Full Redeployment");
        console.log("  EVMBench Audit: 10H/4M/1L - ALL FIXED");
        console.log("========================================================");
        console.log("Deployer     :", deployer);
        console.log("Chain ID     :", block.chainid);
        console.log(
            "Auth         :",
            deployerKey != 0 ? "PRIVATE_KEY" : "--account keystore"
        );
        console.log("Router       :", router);
        console.log("USDT         :", usdt);
        console.log("WBNB         :", wbnb);
        console.log("========================================================");
        console.log("");

        // ══════════════════════════════════════════════════════════
        //  PHASE 1: Deploy 10 contracts + wire + approve
        // ══════════════════════════════════════════════════════════

        console.log("[PHASE 1] Deploying 10 contracts + wiring...");
        console.log("");

        if (deployerKey != 0) {
            vm.startBroadcast(deployerKey);
        } else {
            vm.startBroadcast();
        }

        _phase1_deploy(router, wbnb);

        vm.stopBroadcast();

        console.log("");
        console.log("[PHASE 1] Complete. 10 contracts deployed + wired.");
        console.log("");

        // ══════════════════════════════════════════════════════════
        //  PHASE 2: Template setup (LLM Trader)
        // ══════════════════════════════════════════════════════════

        console.log("[PHASE 2] Setting up LLM template...");
        console.log("");

        if (deployerKey != 0) {
            vm.startBroadcast(deployerKey);
        } else {
            vm.startBroadcast();
        }

        _phase2_template(router, usdt, wbnb);

        vm.stopBroadcast();

        // ══════════════════════════════════════════════════════════
        //  SUMMARY
        // ══════════════════════════════════════════════════════════

        _printSummary();
    }

    // ══════════════════════════════════════════════════════════════
    //  Phase 1: Deploy + Wire + Approve (10 contracts)
    // ══════════════════════════════════════════════════════════════

    function _phase1_deploy(address router, address wbnb) internal {
        // --- Deploy 10 contracts ---
        guardV4 = new PolicyGuardV4();
        console.log("  [ 1/10] PolicyGuardV4       :", address(guardV4));

        nfa = new AgentNFA(address(guardV4));
        console.log("  [ 2/10] AgentNFA            :", address(nfa));

        lm = new ListingManager();
        console.log("  [ 3/11] ListingManager      :", address(lm));

        extensions = new AgentNFAExtensions(address(nfa));
        console.log("  [ 4/11] AgentNFAExtensions  :", address(extensions));

        tokenWL = new TokenWhitelistPolicy(address(guardV4), address(nfa));
        console.log("  [ 4/10] TokenWhitelistPolicy:", address(tokenWL));

        spendingLimit = new SpendingLimitPolicy(address(guardV4), address(nfa));
        console.log("  [ 5/10] SpendingLimitPolicy :", address(spendingLimit));

        cooldown = new CooldownPolicy(address(guardV4), address(nfa));
        console.log("  [ 6/10] CooldownPolicy      :", address(cooldown));

        receiverGuard = new ReceiverGuardPolicy(address(nfa));
        console.log("  [ 7/10] ReceiverGuardPolicy :", address(receiverGuard));

        dexWL = new DexWhitelistPolicy(address(guardV4), address(nfa));
        console.log("  [ 8/10] DexWhitelistPolicy  :", address(dexWL));

        defiGuard = new DeFiGuardPolicy(address(guardV4), address(nfa));
        console.log("  [ 9/10] DeFiGuardPolicy     :", address(defiGuard));

        console.log("  [10/10] AgentAccount        : auto-created on mint");

        // --- Wire contracts ---
        console.log("");
        console.log("  Wiring contracts...");

        guardV4.setAgentNFA(address(nfa));
        console.log("  [wire] GuardV4.setAgentNFA      -> NFA");

        nfa.setListingManager(address(lm));
        console.log("  [wire] NFA.setListingManager     -> LM");

        guardV4.setListingManager(address(lm));
        console.log("  [wire] GuardV4.setListingManager -> LM");

        lm.setPolicyGuard(address(guardV4));
        console.log("  [wire] LM.setPolicyGuard         -> GuardV4");

        // V-001 fix: ListingManager must know the trusted AgentNFA
        lm.setAgentNFA(address(nfa));
        console.log("  [wire] LM.setAgentNFA            -> NFA  (V-001 fix)");

        // --- Approve all 6 policy contracts ---
        console.log("");
        console.log("  Approving 6 policies...");

        guardV4.approvePolicyContract(address(tokenWL));
        console.log("  [approve] TokenWhitelistPolicy");

        guardV4.approvePolicyContract(address(spendingLimit));
        console.log("  [approve] SpendingLimitPolicy");

        guardV4.approvePolicyContract(address(cooldown));
        console.log("  [approve] CooldownPolicy");

        guardV4.approvePolicyContract(address(receiverGuard));
        console.log("  [approve] ReceiverGuardPolicy");

        guardV4.approvePolicyContract(address(dexWL));
        console.log("  [approve] DexWhitelistPolicy");

        guardV4.approvePolicyContract(address(defiGuard));
        console.log("  [approve] DeFiGuardPolicy");

        // --- Configure DeFiGuardPolicy global settings ---
        console.log("");
        console.log("  Configuring DeFiGuardPolicy...");

        defiGuard.addGlobalTarget(router);
        defiGuard.addGlobalTarget(wbnb);
        console.log("  [defi-wl] Global targets: Router, WBNB");

        defiGuard.addSelector(SWAP_EXACT_TOKENS);
        defiGuard.addSelector(SWAP_EXACT_ETH);
        defiGuard.addSelector(SWAP_ETH_EXACT_TOKENS);
        defiGuard.addSelector(SWAP_TOKENS_EXACT_ETH);
        defiGuard.addSelector(SWAP_EXACT_TOKENS_ETH);
        defiGuard.addSelector(APPROVE_SELECTOR);
        defiGuard.addSelector(TRANSFER_SELECTOR);
        defiGuard.addSelector(DEPOSIT_SELECTOR);
        defiGuard.addSelector(WITHDRAW_SELECTOR);
        console.log(
            "  [defi-sel] 9 selectors (5 swap + approve + transfer + deposit + withdraw)"
        );

        // --- Configure SpendingLimitPolicy approved spender ---
        spendingLimit.setApprovedSpender(router, true);
        console.log("  [spend] Approved spender: Router");
    }

    // ══════════════════════════════════════════════════════════════
    //  Phase 2: LLM Template Setup
    // ══════════════════════════════════════════════════════════════

    function _phase2_template(
        address router,
        address usdt,
        address wbnb
    ) internal {
        address deployer = nfa.owner();

        // --- Mint LLM Template Agent ---
        IBAP578.AgentMetadata memory meta = IBAP578.AgentMetadata({
            persona: '{"name":"LLM Trader Agent","description":"AI-powered autonomous trading agent driven by LLM reasoning"}',
            experience: "Template",
            voiceHash: "",
            animationURI: "",
            vaultURI: "",
            vaultHash: bytes32(0)
        });

        uint256 llmTokenId = nfa.mintAgent(
            deployer,
            bytes32(uint256(1)),
            nfa.TYPE_LLM_TRADER(),
            "https://api.shll.run/api/metadata/0",
            meta
        );
        console.log("  [mint]     LLM Template tokenId:", llmTokenId);

        // --- Register as template ---
        nfa.registerTemplate(llmTokenId, TEMPLATE_LLM);
        console.log("  [register] Template key: llm_trader_v3");

        // --- Attach 6 policies to template ---
        guardV4.addTemplatePolicy(TEMPLATE_LLM, address(receiverGuard));
        guardV4.addTemplatePolicy(TEMPLATE_LLM, address(spendingLimit));
        guardV4.addTemplatePolicy(TEMPLATE_LLM, address(tokenWL));
        guardV4.addTemplatePolicy(TEMPLATE_LLM, address(dexWL));
        guardV4.addTemplatePolicy(TEMPLATE_LLM, address(cooldown));
        guardV4.addTemplatePolicy(TEMPLATE_LLM, address(defiGuard));
        console.log("  [policies] 6 policies attached to LLM template");

        // --- Configure spending ceilings ---
        // 10 BNB per tx, 50 BNB per day, 500 bps (5%) max slippage
        spendingLimit.setTemplateCeiling(TEMPLATE_LLM, 10 ether, 50 ether, 500);
        console.log(
            "  [ceiling]  Spending: 10 BNB/tx, 50 BNB/day, 5% slippage"
        );

        // Approve ceiling: 10 BNB max approve amount
        spendingLimit.setTemplateApproveCeiling(TEMPLATE_LLM, 10 ether);
        console.log("  [ceiling]  Approve: 10 BNB max");

        // --- Token whitelist ---
        tokenWL.addToken(llmTokenId, usdt);
        tokenWL.addToken(llmTokenId, wbnb);
        console.log("  [whitelist] Tokens: USDT, WBNB");

        // --- DEX whitelist ---
        dexWL.addDex(llmTokenId, router);
        console.log("  [whitelist] DEX: PancakeSwap Router");

        // --- Cooldown ---
        cooldown.setCooldown(llmTokenId, 60);
        console.log("  [cooldown] 60 seconds");

        // --- List on marketplace ---
        bytes32 listingId = lm.createTemplateListing(
            address(nfa),
            llmTokenId,
            uint96(0.005 ether), // 0.005 BNB per day
            1 // min 1 day
        );
        console.log("  [listing]  Listed at 0.005 BNB/day");
        console.log("  [listing]  Listing ID:");
        console.logBytes32(listingId);
    }

    // ══════════════════════════════════════════════════════════════
    //  Summary Output
    // ══════════════════════════════════════════════════════════════

    function _printSummary() internal view {
        console.log("");
        console.log("========================================================");
        console.log("  V3.2 POST-AUDIT DEPLOYMENT COMPLETE");
        console.log("========================================================");
        console.log("");
        console.log("--- Core Contracts (3) ---");
        console.log("AgentNFA            :", address(nfa));
        console.log("AgentNFAExtensions  :", address(extensions));
        console.log("PolicyGuardV4       :", address(guardV4));
        console.log("ListingManager      :", address(lm));
        console.log("");
        console.log("--- Policy Plugins (6) ---");
        console.log("TokenWhitelistPolicy:", address(tokenWL));
        console.log("SpendingLimitPolicy :", address(spendingLimit));
        console.log("CooldownPolicy      :", address(cooldown));
        console.log("ReceiverGuardPolicy :", address(receiverGuard));
        console.log("DexWhitelistPolicy  :", address(dexWL));
        console.log("DeFiGuardPolicy     :", address(defiGuard));
        console.log("");
        console.log("--- LLM Template ---");
        console.log("Template tokenId    : 0");
        console.log("Ceiling             : 10 BNB/tx, 50 BNB/day, 500 bps");
        console.log("Approve ceiling     : 10 BNB max");
        console.log("Approved spender    : Router");
        console.log("Token whitelist     : USDT, WBNB");
        console.log("DEX whitelist       : Router");
        console.log("Cooldown            : 60s");
        console.log("Listing price       : 0.005 BNB/day");
        console.log("");
        console.log("--- Security (Post-Audit) ---");
        console.log("Fail-close policies : 6/6");
        console.log("Instance soulbound  : YES");
        console.log("Classic rental      : DISABLED");
        console.log("increaseAllowance   : BLOCKED");
        console.log("ERC-2612 permit     : BLOCKED");
        console.log("NFA whitelist (V-001): YES");
        console.log("");
        console.log("========================================================");
        console.log("  ENV VARIABLES (copy to .env)");
        console.log("========================================================");
        console.log("");
        console.log(string.concat("AGENT_NFA=", vm.toString(address(nfa))));
        console.log(
            string.concat("POLICY_GUARD_V4=", vm.toString(address(guardV4)))
        );
        console.log(
            string.concat("LISTING_MANAGER=", vm.toString(address(lm)))
        );
        console.log(string.concat("TOKEN_WL=", vm.toString(address(tokenWL))));
        console.log(
            string.concat(
                "SPENDING_LIMIT=",
                vm.toString(address(spendingLimit))
            )
        );
        console.log(string.concat("COOLDOWN=", vm.toString(address(cooldown))));
        console.log(
            string.concat(
                "RECEIVER_GUARD=",
                vm.toString(address(receiverGuard))
            )
        );
        console.log(string.concat("DEX_WL=", vm.toString(address(dexWL))));
        console.log(
            string.concat("DEFI_GUARD=", vm.toString(address(defiGuard)))
        );
        console.log("");
        console.log("--- Indexer Env ---");
        console.log(
            string.concat("AGENT_NFA_ADDRESS=", vm.toString(address(nfa)))
        );
        console.log(
            string.concat("LISTING_MANAGER_ADDRESS=", vm.toString(address(lm)))
        );
        console.log(
            string.concat(
                "POLICY_GUARD_V4_ADDRESS=",
                vm.toString(address(guardV4))
            )
        );
        console.log(
            string.concat("CONTRACT_START_BLOCK=", vm.toString(block.number))
        );
        console.log("");
        console.log("--- Frontend Env ---");
        console.log(
            string.concat("NEXT_PUBLIC_AGENT_NFA=", vm.toString(address(nfa)))
        );
        console.log(
            string.concat(
                "NEXT_PUBLIC_LISTING_MANAGER=",
                vm.toString(address(lm))
            )
        );
        console.log(
            string.concat(
                "NEXT_PUBLIC_POLICY_GUARD_V3=",
                vm.toString(address(guardV4))
            )
        );
        console.log(
            string.concat(
                "NEXT_PUBLIC_DEPLOY_BLOCK=",
                vm.toString(block.number)
            )
        );
        console.log("");
        console.log("========================================================");
        console.log("  Total: 10 deployed + 1 auto-created = 11 contracts");
        console.log("========================================================");
    }
}
