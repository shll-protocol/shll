// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {ProtocolRegistry} from "../src/ProtocolRegistry.sol";
import {ReceiverGuardPolicyV2} from "../src/policies/ReceiverGuardPolicyV2.sol";
import {DeFiGuardPolicyV2} from "../src/policies/DeFiGuardPolicyV2.sol";
import {SpendingLimitPolicyV2} from "../src/policies/SpendingLimitPolicyV2.sol";
import {PolicyGuardV4} from "../src/PolicyGuardV4.sol";

/// @title ProtocolRegistry Tests — unified protocol registration
contract ProtocolRegistryTest is Test {
    ProtocolRegistry public registry;
    PolicyGuardV4 public guard;
    ReceiverGuardPolicyV2 public receiverGuard;
    DeFiGuardPolicyV2 public defiGuard;
    SpendingLimitPolicyV2 public spendingLimit;

    address constant OWNER = address(0x1);
    address constant NFA = address(0xBBBB);
    address constant STRANGER = address(0xDEAD);

    // Test protocol data
    address constant TARGET_ROUTER = address(0xD99D);
    address constant TARGET_WBNB = address(0xBBFF);
    bytes4 constant SEL_SWAP_EXACT_ETH = 0x7ff36ab5;
    bytes4 constant SEL_SWAP_EXACT_TOKENS = 0x38ed1739;
    bytes4 constant SEL_APPROVE = 0x095ea7b3;
    bytes4 constant SEL_FOUR_MEME_BUY = 0x3deec419;

    bytes32 constant PROTO_ID = keccak256("TEST_PROTOCOL");
    bytes32 constant PROTO_ID_2 = keccak256("TEST_PROTOCOL_2");

    function setUp() public {
        vm.startPrank(OWNER);

        // Deploy PolicyGuardV4 (Ownable2Step, deployer = OWNER)
        guard = new PolicyGuardV4();

        // Deploy all 3 policies pointing to guard + NFA
        receiverGuard = new ReceiverGuardPolicyV2(NFA, address(guard));
        defiGuard = new DeFiGuardPolicyV2(address(guard), NFA);
        spendingLimit = new SpendingLimitPolicyV2(address(guard), NFA);

        // Deploy ProtocolRegistry
        registry = new ProtocolRegistry(
            address(receiverGuard),
            address(defiGuard),
            address(spendingLimit),
            address(guard)
        );

        // Transfer PolicyGuardV4 ownership to Registry (Ownable2Step: 2-step)
        guard.transferOwnership(address(registry));
        vm.stopPrank();

        // Registry accepts ownership
        vm.prank(OWNER);
        registry.acceptGuardOwnership();
    }

    // ═══════════════════════════════════════════════════════
    //              SETUP VERIFICATION
    // ═══════════════════════════════════════════════════════

    function test_setUp_guardOwnerIsRegistry() public view {
        assertEq(guard.owner(), address(registry));
    }

    function test_setUp_registryOwnerIsDeployer() public view {
        assertEq(registry.owner(), OWNER);
    }

    function test_constructor_zeroAddress_reverts() public {
        vm.expectRevert(ProtocolRegistry.ZeroAddress.selector);
        new ProtocolRegistry(
            address(0),
            address(defiGuard),
            address(spendingLimit),
            address(guard)
        );

        vm.expectRevert(ProtocolRegistry.ZeroAddress.selector);
        new ProtocolRegistry(
            address(receiverGuard),
            address(0),
            address(spendingLimit),
            address(guard)
        );

        vm.expectRevert(ProtocolRegistry.ZeroAddress.selector);
        new ProtocolRegistry(
            address(receiverGuard),
            address(defiGuard),
            address(0),
            address(guard)
        );

        vm.expectRevert(ProtocolRegistry.ZeroAddress.selector);
        new ProtocolRegistry(
            address(receiverGuard),
            address(defiGuard),
            address(spendingLimit),
            address(0)
        );
    }

    // ═══════════════════════════════════════════════════════
    //              REGISTER PROTOCOL
    // ═══════════════════════════════════════════════════════

    function test_registerProtocol() public {
        _registerTestProtocol();

        // Verify on-chain storage
        ProtocolRegistry.ProtocolConfig memory p = registry.getProtocol(
            PROTO_ID
        );
        assertTrue(p.active, "Protocol should be active");
        assertEq(p.name, "TestDEX");
        assertEq(p.allSelectors.length, 2);
        assertEq(p.buySelectors.length, 1);
        assertEq(p.targets.length, 2);
        assertEq(p.receiverPattern, 2);

        // Verify ReceiverGuard state
        assertEq(receiverGuard.selectorPattern(SEL_SWAP_EXACT_ETH), 2);

        // Verify DeFiGuard state
        assertTrue(defiGuard.allowedSelectors(SEL_SWAP_EXACT_ETH));
        assertTrue(defiGuard.allowedSelectors(SEL_SWAP_EXACT_TOKENS));
        assertTrue(defiGuard.globalAllowed(TARGET_ROUTER));
        assertTrue(defiGuard.globalAllowed(TARGET_WBNB));

        // Verify SpendingLimit state
        assertTrue(spendingLimit.approvedSpender(TARGET_ROUTER));
        assertTrue(spendingLimit.approvedSpender(TARGET_WBNB));

        // Verify ref counts
        assertEq(registry.selectorRefCount(SEL_SWAP_EXACT_ETH), 1);
        assertEq(registry.selectorRefCount(SEL_SWAP_EXACT_TOKENS), 1);
        assertEq(registry.targetRefCount(TARGET_ROUTER), 1);
        assertEq(registry.targetRefCount(TARGET_WBNB), 1);
    }

    function test_registerProtocol_emitsEvent() public {
        ProtocolRegistry.ProtocolConfig memory config = _buildTestConfig();

        vm.expectEmit(true, false, false, true);
        emit ProtocolRegistry.ProtocolRegistered(PROTO_ID, "TestDEX", 2, 2);

        vm.prank(OWNER);
        registry.registerProtocol(PROTO_ID, config);
    }

    function test_registerProtocol_noBuySelectors() public {
        bytes4[] memory allSels = new bytes4[](1);
        allSels[0] = SEL_APPROVE;

        bytes4[] memory buySels = new bytes4[](0);
        address[] memory targets = new address[](1);
        targets[0] = TARGET_ROUTER;

        ProtocolRegistry.ProtocolConfig memory config = ProtocolRegistry
            .ProtocolConfig({
                name: "SellOnly",
                allSelectors: allSels,
                buySelectors: buySels,
                receiverPattern: 0,
                targets: targets,
                active: false
            });

        vm.prank(OWNER);
        registry.registerProtocol(PROTO_ID, config);

        ProtocolRegistry.ProtocolConfig memory p = registry.getProtocol(
            PROTO_ID
        );
        assertTrue(p.active);
        assertEq(p.buySelectors.length, 0);
    }

    function test_registerProtocol_duplicate_reverts() public {
        _registerTestProtocol();

        ProtocolRegistry.ProtocolConfig memory config = _buildTestConfig();
        vm.prank(OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(
                ProtocolRegistry.ProtocolAlreadyExists.selector,
                PROTO_ID
            )
        );
        registry.registerProtocol(PROTO_ID, config);
    }

    function test_registerProtocol_idempotent_selectors() public {
        // Pre-register a selector in DeFiGuard via emergencyCall
        vm.prank(OWNER);
        registry.emergencyCall(
            address(defiGuard),
            abi.encodeWithSelector(
                defiGuard.addSelector.selector,
                SEL_SWAP_EXACT_ETH
            )
        );
        assertTrue(defiGuard.allowedSelectors(SEL_SWAP_EXACT_ETH));

        // Registration should not revert — skips existing selector in policy
        _registerTestProtocol();
        assertTrue(defiGuard.allowedSelectors(SEL_SWAP_EXACT_ETH));
    }

    // ═══════════════════════════════════════════════════════
    //              REMOVE PROTOCOL
    // ═══════════════════════════════════════════════════════

    function test_registerProtocol_buySelectorPatternZero_reverts() public {
        bytes4[] memory allSels = new bytes4[](1);
        allSels[0] = SEL_SWAP_EXACT_ETH;

        bytes4[] memory buySels = new bytes4[](1);
        buySels[0] = SEL_SWAP_EXACT_ETH;

        address[] memory targets = new address[](1);
        targets[0] = TARGET_ROUTER;

        vm.prank(OWNER);
        vm.expectRevert(ProtocolRegistry.InvalidReceiverPattern.selector);
        registry.registerProtocol(
            PROTO_ID,
            ProtocolRegistry.ProtocolConfig({
                name: "BadPattern",
                allSelectors: allSels,
                buySelectors: buySels,
                receiverPattern: 0,
                targets: targets,
                active: false
            })
        );
    }

    function test_registerProtocol_buySelectorPatternUnknown_reverts() public {
        bytes4[] memory allSels = new bytes4[](1);
        allSels[0] = SEL_FOUR_MEME_BUY;

        bytes4[] memory buySels = new bytes4[](1);
        buySels[0] = SEL_FOUR_MEME_BUY;

        address[] memory targets = new address[](1);
        targets[0] = TARGET_ROUTER;

        vm.prank(OWNER);
        vm.expectRevert(ProtocolRegistry.InvalidReceiverPattern.selector);
        registry.registerProtocol(
            PROTO_ID,
            ProtocolRegistry.ProtocolConfig({
                name: "BadPatternUnknown",
                allSelectors: allSels,
                buySelectors: buySels,
                receiverPattern: 6,
                targets: targets,
                active: false
            })
        );
    }

    function test_registerProtocol_duplicateBuySelectors_countOnce() public {
        bytes4[] memory allSels = new bytes4[](1);
        allSels[0] = SEL_SWAP_EXACT_ETH;

        bytes4[] memory buySels = new bytes4[](2);
        buySels[0] = SEL_SWAP_EXACT_ETH;
        buySels[1] = SEL_SWAP_EXACT_ETH;

        address[] memory targets = new address[](1);
        targets[0] = TARGET_ROUTER;

        vm.prank(OWNER);
        registry.registerProtocol(
            PROTO_ID,
            ProtocolRegistry.ProtocolConfig({
                name: "DupBuySelector",
                allSelectors: allSels,
                buySelectors: buySels,
                receiverPattern: 2,
                targets: targets,
                active: false
            })
        );

        assertEq(registry.buySelectorRefCount(SEL_SWAP_EXACT_ETH), 1);
        assertEq(receiverGuard.selectorPattern(SEL_SWAP_EXACT_ETH), 2);
    }

    function test_sharedBuySelector_samePattern_refCounted() public {
        _registerTestProtocol();
        assertEq(registry.buySelectorRefCount(SEL_SWAP_EXACT_ETH), 1);
        assertEq(receiverGuard.selectorPattern(SEL_SWAP_EXACT_ETH), 2);

        bytes4[] memory allSels2 = new bytes4[](1);
        allSels2[0] = SEL_APPROVE;

        bytes4[] memory buySels2 = new bytes4[](1);
        buySels2[0] = SEL_SWAP_EXACT_ETH;

        address[] memory targets2 = new address[](1);
        targets2[0] = address(0xAAAA);

        vm.prank(OWNER);
        registry.registerProtocol(
            PROTO_ID_2,
            ProtocolRegistry.ProtocolConfig({
                name: "Proto2Buy",
                allSelectors: allSels2,
                buySelectors: buySels2,
                receiverPattern: 2,
                targets: targets2,
                active: false
            })
        );

        assertEq(registry.buySelectorRefCount(SEL_SWAP_EXACT_ETH), 2);
        assertEq(receiverGuard.selectorPattern(SEL_SWAP_EXACT_ETH), 2);

        vm.prank(OWNER);
        registry.removeProtocol(PROTO_ID);
        assertEq(registry.buySelectorRefCount(SEL_SWAP_EXACT_ETH), 1);
        assertEq(receiverGuard.selectorPattern(SEL_SWAP_EXACT_ETH), 2);

        vm.prank(OWNER);
        registry.removeProtocol(PROTO_ID_2);
        assertEq(registry.buySelectorRefCount(SEL_SWAP_EXACT_ETH), 0);
        // This selector is constructor-hardcoded in ReceiverGuardV2, so
        // Registry removal must not wipe the pre-existing pattern.
        assertEq(receiverGuard.selectorPattern(SEL_SWAP_EXACT_ETH), 2);
    }

    function test_sharedBuySelector_patternMismatch_reverts() public {
        _registerTestProtocol();

        bytes4[] memory allSels2 = new bytes4[](1);
        allSels2[0] = SEL_APPROVE;

        bytes4[] memory buySels2 = new bytes4[](1);
        buySels2[0] = SEL_SWAP_EXACT_ETH;

        address[] memory targets2 = new address[](1);
        targets2[0] = address(0xAAAA);

        vm.prank(OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(
                ProtocolRegistry.BuySelectorPatternMismatch.selector,
                SEL_SWAP_EXACT_ETH,
                uint8(2),
                uint8(3)
            )
        );
        registry.registerProtocol(
            PROTO_ID_2,
            ProtocolRegistry.ProtocolConfig({
                name: "Proto2Mismatch",
                allSelectors: allSels2,
                buySelectors: buySels2,
                receiverPattern: 3,
                targets: targets2,
                active: false
            })
        );
    }

    function test_removeProtocol() public {
        _registerTestProtocol();

        vm.prank(OWNER);
        registry.removeProtocol(PROTO_ID);

        // Verify on-chain storage is fully cleaned
        ProtocolRegistry.ProtocolConfig memory p = registry.getProtocol(
            PROTO_ID
        );
        assertFalse(p.active, "Protocol should be inactive");
        assertEq(p.allSelectors.length, 0, "allSelectors should be cleared");
        assertEq(p.buySelectors.length, 0, "buySelectors should be cleared");
        assertEq(p.targets.length, 0, "targets should be cleared");
        assertEq(bytes(p.name).length, 0, "name should be cleared");

        // This selector was already hardcoded by ReceiverGuard constructor.
        // removeProtocol() must not delete pre-existing chain state.
        assertEq(receiverGuard.selectorPattern(SEL_SWAP_EXACT_ETH), 2);

        // Verify DeFiGuard cleared
        assertFalse(defiGuard.allowedSelectors(SEL_SWAP_EXACT_ETH));
        assertFalse(defiGuard.allowedSelectors(SEL_SWAP_EXACT_TOKENS));
        assertFalse(defiGuard.globalAllowed(TARGET_ROUTER));
        assertFalse(defiGuard.globalAllowed(TARGET_WBNB));

        // Verify SpendingLimit cleared
        assertFalse(spendingLimit.approvedSpender(TARGET_ROUTER));
        assertFalse(spendingLimit.approvedSpender(TARGET_WBNB));

        // Verify ref counts are 0
        assertEq(registry.selectorRefCount(SEL_SWAP_EXACT_ETH), 0);
        assertEq(registry.targetRefCount(TARGET_ROUTER), 0);

        // Verify removed from protocolIds
        assertEq(registry.protocolCount(), 0);
    }

    function test_removeProtocol_managedBuySelector_clearsPattern() public {
        bytes4[] memory allSels = new bytes4[](1);
        allSels[0] = SEL_FOUR_MEME_BUY;

        bytes4[] memory buySels = new bytes4[](1);
        buySels[0] = SEL_FOUR_MEME_BUY;

        address[] memory targets = new address[](1);
        targets[0] = TARGET_ROUTER;

        vm.prank(OWNER);
        registry.registerProtocol(
            PROTO_ID,
            ProtocolRegistry.ProtocolConfig({
                name: "ManagedBuySel",
                allSelectors: allSels,
                buySelectors: buySels,
                receiverPattern: 5,
                targets: targets,
                active: false
            })
        );

        assertEq(receiverGuard.selectorPattern(SEL_FOUR_MEME_BUY), 5);
        assertTrue(registry.managedBuySelector(SEL_FOUR_MEME_BUY));

        vm.prank(OWNER);
        registry.removeProtocol(PROTO_ID);

        assertEq(registry.buySelectorRefCount(SEL_FOUR_MEME_BUY), 0);
        assertEq(receiverGuard.selectorPattern(SEL_FOUR_MEME_BUY), 0);
    }

    function test_removeProtocol_preservesPreExistingSelectorState() public {
        // Pre-existing selector from out-of-band ops (not managed by Registry)
        vm.prank(OWNER);
        registry.emergencyCall(
            address(defiGuard),
            abi.encodeWithSelector(
                defiGuard.addSelector.selector,
                SEL_APPROVE
            )
        );
        assertTrue(defiGuard.allowedSelectors(SEL_APPROVE));

        bytes4[] memory allSels = new bytes4[](1);
        allSels[0] = SEL_APPROVE;

        bytes4[] memory buySels = new bytes4[](0);
        address[] memory targets = new address[](1);
        targets[0] = TARGET_ROUTER;

        vm.prank(OWNER);
        registry.registerProtocol(
            PROTO_ID,
            ProtocolRegistry.ProtocolConfig({
                name: "LegacySelector",
                allSelectors: allSels,
                buySelectors: buySels,
                receiverPattern: 0,
                targets: targets,
                active: false
            })
        );

        assertEq(registry.selectorRefCount(SEL_APPROVE), 1);
        assertFalse(registry.managedSelector(SEL_APPROVE));

        vm.prank(OWNER);
        registry.removeProtocol(PROTO_ID);

        // Must stay enabled because Registry did not add it.
        assertTrue(defiGuard.allowedSelectors(SEL_APPROVE));
    }

    function test_removeProtocol_preservesPreExistingTargetAndSpenderState() public {
        // Pre-existing target/spender from out-of-band ops (not managed by Registry)
        vm.prank(OWNER);
        registry.emergencyCall(
            address(defiGuard),
            abi.encodeWithSelector(
                defiGuard.addGlobalTarget.selector,
                TARGET_ROUTER
            )
        );
        vm.prank(OWNER);
        registry.emergencyCall(
            address(spendingLimit),
            abi.encodeWithSelector(
                spendingLimit.setApprovedSpender.selector,
                TARGET_ROUTER,
                true
            )
        );

        assertTrue(defiGuard.globalAllowed(TARGET_ROUTER));
        assertTrue(spendingLimit.approvedSpender(TARGET_ROUTER));

        bytes4[] memory allSels = new bytes4[](1);
        allSels[0] = SEL_APPROVE;
        bytes4[] memory buySels = new bytes4[](0);
        address[] memory targets = new address[](1);
        targets[0] = TARGET_ROUTER;

        vm.prank(OWNER);
        registry.registerProtocol(
            PROTO_ID,
            ProtocolRegistry.ProtocolConfig({
                name: "LegacyTarget",
                allSelectors: allSels,
                buySelectors: buySels,
                receiverPattern: 0,
                targets: targets,
                active: false
            })
        );

        assertEq(registry.targetRefCount(TARGET_ROUTER), 1);
        assertFalse(registry.managedGlobalTarget(TARGET_ROUTER));
        assertFalse(registry.managedApprovedSpender(TARGET_ROUTER));

        vm.prank(OWNER);
        registry.removeProtocol(PROTO_ID);

        // Must stay enabled because Registry did not add them.
        assertTrue(defiGuard.globalAllowed(TARGET_ROUTER));
        assertTrue(spendingLimit.approvedSpender(TARGET_ROUTER));
    }

    function test_removeProtocol_emitsEvent() public {
        _registerTestProtocol();

        vm.expectEmit(true, false, false, true);
        emit ProtocolRegistry.ProtocolRemoved(PROTO_ID, "TestDEX");

        vm.prank(OWNER);
        registry.removeProtocol(PROTO_ID);
    }

    function test_removeProtocol_notFound_reverts() public {
        vm.prank(OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(
                ProtocolRegistry.ProtocolNotFound.selector,
                PROTO_ID
            )
        );
        registry.removeProtocol(PROTO_ID);
    }

    // ═══════════════════════════════════════════════════════
    //    CRITICAL: Shared Selector/Target Collision (C-1)
    // ═══════════════════════════════════════════════════════

    function test_sharedSelector_removeOneProtocol_otherKeepsWorking() public {
        // Both protocols share SEL_APPROVE and TARGET_ROUTER
        _registerTestProtocol(); // uses SEL_SWAP_EXACT_ETH, SEL_SWAP_EXACT_TOKENS, TARGET_ROUTER, TARGET_WBNB

        // Register second protocol that also uses TARGET_ROUTER
        bytes4[] memory allSels2 = new bytes4[](1);
        allSels2[0] = SEL_SWAP_EXACT_TOKENS; // shared selector!

        address[] memory targets2 = new address[](1);
        targets2[0] = TARGET_ROUTER; // shared target!

        vm.prank(OWNER);
        registry.registerProtocol(
            PROTO_ID_2,
            ProtocolRegistry.ProtocolConfig({
                name: "Proto2",
                allSelectors: allSels2,
                buySelectors: new bytes4[](0),
                receiverPattern: 0,
                targets: targets2,
                active: false
            })
        );

        // Verify ref counts
        assertEq(registry.selectorRefCount(SEL_SWAP_EXACT_TOKENS), 2);
        assertEq(registry.targetRefCount(TARGET_ROUTER), 2);

        // Remove first protocol
        vm.prank(OWNER);
        registry.removeProtocol(PROTO_ID);

        // CRITICAL: Shared selector and target must still be active
        assertTrue(
            defiGuard.allowedSelectors(SEL_SWAP_EXACT_TOKENS),
            "Shared selector should still be active after removing one protocol"
        );
        assertTrue(
            defiGuard.globalAllowed(TARGET_ROUTER),
            "Shared target should still be active after removing one protocol"
        );
        assertTrue(
            spendingLimit.approvedSpender(TARGET_ROUTER),
            "Shared spender should still be active after removing one protocol"
        );

        // Non-shared should be removed
        assertFalse(defiGuard.allowedSelectors(SEL_SWAP_EXACT_ETH));
        assertFalse(defiGuard.globalAllowed(TARGET_WBNB));

        // Verify ref counts decremented
        assertEq(registry.selectorRefCount(SEL_SWAP_EXACT_TOKENS), 1);
        assertEq(registry.targetRefCount(TARGET_ROUTER), 1);

        // Remove second protocol — now shared items should be removed
        vm.prank(OWNER);
        registry.removeProtocol(PROTO_ID_2);

        assertFalse(defiGuard.allowedSelectors(SEL_SWAP_EXACT_TOKENS));
        assertFalse(defiGuard.globalAllowed(TARGET_ROUTER));
        assertFalse(spendingLimit.approvedSpender(TARGET_ROUTER));
        assertEq(registry.selectorRefCount(SEL_SWAP_EXACT_TOKENS), 0);
    }

    // ═══════════════════════════════════════════════════════
    //    CRITICAL: Re-register After Remove (C-2)
    // ═══════════════════════════════════════════════════════

    function test_reRegisterAfterRemove_cleanData() public {
        _registerTestProtocol();

        vm.prank(OWNER);
        registry.removeProtocol(PROTO_ID);

        // Re-register with same ID — should work cleanly
        _registerTestProtocol();

        ProtocolRegistry.ProtocolConfig memory p = registry.getProtocol(
            PROTO_ID
        );
        assertTrue(p.active);
        // Must be exactly 2, not 4 (would be 4 if old data wasn't cleared)
        assertEq(
            p.allSelectors.length,
            2,
            "Should have exact selector count, not doubled"
        );
        assertEq(
            p.buySelectors.length,
            1,
            "Should have exact buy selector count"
        );
        assertEq(p.targets.length, 2, "Should have exact target count");
        assertEq(registry.protocolCount(), 1);
    }

    // ═══════════════════════════════════════════════════════
    //              LIST / QUERY
    // ═══════════════════════════════════════════════════════

    function test_listProtocols() public {
        _registerTestProtocol();
        _registerSecondProtocol();

        bytes32[] memory ids = registry.listProtocols();
        assertEq(ids.length, 2);
    }

    function test_listProtocols_afterRemove() public {
        _registerTestProtocol();
        _registerSecondProtocol();

        vm.prank(OWNER);
        registry.removeProtocol(PROTO_ID);

        bytes32[] memory ids = registry.listProtocols();
        assertEq(ids.length, 1);
        assertEq(ids[0], PROTO_ID_2);
    }

    function test_protocolCount() public {
        assertEq(registry.protocolCount(), 0);
        _registerTestProtocol();
        assertEq(registry.protocolCount(), 1);
        _registerSecondProtocol();
        assertEq(registry.protocolCount(), 2);
    }

    // ═══════════════════════════════════════════════════════
    //              EMERGENCY CALL
    // ═══════════════════════════════════════════════════════

    function test_emergencyCall() public {
        vm.prank(OWNER);
        registry.emergencyCall(
            address(defiGuard),
            abi.encodeWithSelector(
                defiGuard.addBlacklist.selector,
                address(0xBAD)
            )
        );

        assertTrue(defiGuard.globalBlacklisted(address(0xBAD)));
    }

    function test_emergencyCall_onlyOwner() public {
        vm.prank(STRANGER);
        vm.expectRevert("Ownable: caller is not the owner");
        registry.emergencyCall(address(defiGuard), "");
    }

    function test_emergencyCall_failedCall_reverts() public {
        vm.prank(OWNER);
        vm.expectRevert();
        registry.emergencyCall(
            address(defiGuard),
            abi.encodeWithSelector(bytes4(0xdeadbeef))
        );
    }

    // ═══════════════════════════════════════════════════════
    //              GUARD CALL (PolicyGuardV4 proxy)
    // ═══════════════════════════════════════════════════════

    function test_guardCall_setAgentNFA() public {
        address newNFA = address(0x9999);
        vm.prank(OWNER);
        registry.guardCall(
            abi.encodeWithSelector(guard.setAgentNFA.selector, newNFA)
        );
        assertEq(guard.agentNFA(), newNFA);
    }

    function test_guardCall_approvePolicyContract() public {
        address fakePolicy = address(0x7777);
        vm.prank(OWNER);
        registry.guardCall(
            abi.encodeWithSelector(
                guard.approvePolicyContract.selector,
                fakePolicy
            )
        );
        assertTrue(guard.approvedPolicies(fakePolicy));
    }

    function test_guardCall_onlyOwner() public {
        vm.prank(STRANGER);
        vm.expectRevert("Ownable: caller is not the owner");
        registry.guardCall(
            abi.encodeWithSelector(guard.setAgentNFA.selector, address(0))
        );
    }

    // ═══════════════════════════════════════════════════════
    //              ACCESS CONTROL
    // ═══════════════════════════════════════════════════════

    function test_registerProtocol_onlyOwner() public {
        ProtocolRegistry.ProtocolConfig memory config = _buildTestConfig();

        vm.prank(STRANGER);
        vm.expectRevert("Ownable: caller is not the owner");
        registry.registerProtocol(PROTO_ID, config);
    }

    function test_removeProtocol_onlyOwner() public {
        _registerTestProtocol();

        vm.prank(STRANGER);
        vm.expectRevert("Ownable: caller is not the owner");
        registry.removeProtocol(PROTO_ID);
    }

    // ═══════════════════════════════════════════════════════
    //                    HELPERS
    // ═══════════════════════════════════════════════════════

    function _buildTestConfig()
        internal
        pure
        returns (ProtocolRegistry.ProtocolConfig memory)
    {
        bytes4[] memory allSels = new bytes4[](2);
        allSels[0] = SEL_SWAP_EXACT_ETH;
        allSels[1] = SEL_SWAP_EXACT_TOKENS;

        bytes4[] memory buySels = new bytes4[](1);
        buySels[0] = SEL_SWAP_EXACT_ETH;

        address[] memory targets = new address[](2);
        targets[0] = TARGET_ROUTER;
        targets[1] = TARGET_WBNB;

        return
            ProtocolRegistry.ProtocolConfig({
                name: "TestDEX",
                allSelectors: allSels,
                buySelectors: buySels,
                receiverPattern: 2,
                targets: targets,
                active: false // ignored on input
            });
    }

    function _registerTestProtocol() internal {
        ProtocolRegistry.ProtocolConfig memory config = _buildTestConfig();
        vm.prank(OWNER);
        registry.registerProtocol(PROTO_ID, config);
    }

    function _registerSecondProtocol() internal {
        bytes4[] memory allSels = new bytes4[](1);
        allSels[0] = SEL_APPROVE;

        bytes4[] memory buySels = new bytes4[](0);

        address[] memory targets = new address[](1);
        targets[0] = address(0xAAAA);

        ProtocolRegistry.ProtocolConfig memory config = ProtocolRegistry
            .ProtocolConfig({
                name: "SecondProto",
                allSelectors: allSels,
                buySelectors: buySels,
                receiverPattern: 0,
                targets: targets,
                active: false
            });

        vm.prank(OWNER);
        registry.registerProtocol(PROTO_ID_2, config);
    }
}
