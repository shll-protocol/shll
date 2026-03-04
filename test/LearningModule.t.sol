// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentNFA} from "../src/AgentNFA.sol";
import {LearningModule} from "../src/LearningModule.sol";
import {PolicyGuardV4} from "../src/PolicyGuardV4.sol";
import {IBAP578} from "../src/interfaces/IBAP578.sol";
import {Errors} from "../src/libs/Errors.sol";

contract LearningModuleTest is Test {
    AgentNFA public nfa;
    PolicyGuardV4 public guard;
    LearningModule public learning;

    address internal constant TEMPLATE_OWNER = address(0x1111);
    address internal constant RENTER = address(0x2222);
    address internal constant OPERATOR = address(0x3333);
    address internal constant OTHER = address(0x4444);

    bytes32 internal constant POLICY_ID = keccak256("default_policy");
    bytes32 internal constant TEMPLATE_KEY = keccak256("learning-template");
    string internal constant TOKEN_URI = "https://shll.run/metadata/learning.json";

    uint256 internal templateId;
    uint256 internal instanceId;
    uint64 internal leaseExpires;

    function setUp() public {
        guard = new PolicyGuardV4();
        nfa = new AgentNFA(address(guard));
        learning = new LearningModule(address(nfa));

        nfa.setLearningModule(address(learning));
        nfa.setListingManager(address(this));

        leaseExpires = uint64(block.timestamp + 7 days);

        templateId = nfa.mintAgent(
            TEMPLATE_OWNER,
            POLICY_ID,
            nfa.TYPE_LLM_TRADER(),
            TOKEN_URI,
            _buildMetadata()
        );

        vm.prank(TEMPLATE_OWNER);
        nfa.registerTemplate(templateId, TEMPLATE_KEY);

        instanceId = nfa.mintInstanceFromTemplate(
            RENTER,
            templateId,
            leaseExpires,
            abi.encodePacked("init")
        );

        vm.prank(RENTER);
        nfa.setOperator(instanceId, OPERATOR, leaseExpires);
    }

    function test_enableLearning_onlyOwner() public {
        vm.prank(OTHER);
        vm.expectRevert(Errors.OnlyOwner.selector);
        learning.enableLearning(instanceId, true);
    }

    function test_enableLearning_toggle() public {
        assertFalse(nfa.learningEnabled(instanceId));

        vm.prank(RENTER);
        learning.enableLearning(instanceId, true);
        assertTrue(nfa.learningEnabled(instanceId));

        vm.prank(RENTER);
        learning.enableLearning(instanceId, false);
        assertFalse(nfa.learningEnabled(instanceId));
    }

    function test_appendLearning_revertsWhenLearningDisabled() public {
        vm.prank(OPERATOR);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.AgentPaused.selector, instanceId)
        );
        learning.appendLearning(
            instanceId,
            keccak256("leaf-1"),
            keccak256("root-1")
        );
    }

    function test_appendLearning_onlyOperator() public {
        vm.prank(RENTER);
        learning.enableLearning(instanceId, true);

        vm.prank(OTHER);
        vm.expectRevert(Errors.Unauthorized.selector);
        learning.appendLearning(
            instanceId,
            keccak256("leaf-1"),
            keccak256("root-1")
        );
    }

    function test_appendLearning_updatesRootAndCount() public {
        vm.prank(RENTER);
        learning.enableLearning(instanceId, true);

        bytes32 root1 = keccak256("root-1");
        bytes32 root2 = keccak256("root-2");

        vm.prank(OPERATOR);
        learning.appendLearning(instanceId, keccak256("leaf-1"), root1);
        assertEq(nfa.learningTreeRoot(instanceId), root1);
        assertEq(nfa.learningLeafCount(instanceId), 1);

        vm.prank(OPERATOR);
        learning.appendLearning(instanceId, keccak256("leaf-2"), root2);
        assertEq(nfa.learningTreeRoot(instanceId), root2);
        assertEq(nfa.learningLeafCount(instanceId), 2);
    }

    function test_batchAppendLearning_emptyLeavesRevert() public {
        vm.prank(RENTER);
        learning.enableLearning(instanceId, true);

        bytes32[] memory leaves = new bytes32[](0);
        vm.prank(OPERATOR);
        vm.expectRevert(Errors.InvalidInitParams.selector);
        learning.batchAppendLearning(instanceId, leaves, keccak256("root-batch"));
    }

    function test_batchAppendLearning_updatesLeafCount() public {
        vm.prank(RENTER);
        learning.enableLearning(instanceId, true);

        bytes32[] memory leaves = new bytes32[](3);
        leaves[0] = keccak256("leaf-a");
        leaves[1] = keccak256("leaf-b");
        leaves[2] = keccak256("leaf-c");
        bytes32 newRoot = keccak256("root-batch");

        vm.prank(OPERATOR);
        learning.batchAppendLearning(instanceId, leaves, newRoot);

        assertEq(nfa.learningTreeRoot(instanceId), newRoot);
        assertEq(nfa.learningLeafCount(instanceId), 3);
    }

    function test_getLearningMetrics() public {
        vm.prank(RENTER);
        learning.enableLearning(instanceId, true);

        bytes32 newRoot = keccak256("root-final");
        vm.prank(OPERATOR);
        learning.appendLearning(instanceId, keccak256("leaf-1"), newRoot);

        (
            bool enabled,
            bytes32 root,
            uint256 totalLeaves
        ) = learning.getLearningMetrics(instanceId);

        assertTrue(enabled);
        assertEq(root, newRoot);
        assertEq(totalLeaves, 1);
    }

    function test_setLearningData_onlyLearningModule() public {
        vm.prank(OTHER);
        vm.expectRevert(Errors.Unauthorized.selector);
        nfa.setLearningData(instanceId, bytes32(uint256(123)), 77);
    }

    function _buildMetadata()
        internal
        pure
        returns (IBAP578.AgentMetadata memory)
    {
        return
            IBAP578.AgentMetadata({
                persona: "{\"role\":\"trader\"}",
                experience: "learning agent",
                voiceHash: "",
                animationURI: "",
                vaultURI: "",
                vaultHash: bytes32(0)
            });
    }
}
