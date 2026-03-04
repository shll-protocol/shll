// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ILearningModule} from "./interfaces/ILearningModule.sol";
import {Errors} from "./libs/Errors.sol";

/// @title IAgentNFALearning — minimal interface for LearningModule to write data back to AgentNFA
interface IAgentNFALearning {
    function operatorOf(uint256 tokenId) external view returns (address);
    function ownerOf(uint256 tokenId) external view returns (address);
    function setLearningData(
        uint256 tokenId,
        bytes32 newRoot,
        uint256 newLeafCount
    ) external;
    function setLearningEnabled(uint256 tokenId, bool enabled) external;
    function learningEnabled(uint256 tokenId) external view returns (bool);
    function learningTreeRoot(uint256 tokenId) external view returns (bytes32);
    function learningLeafCount(uint256 tokenId) external view returns (uint256);
}

/// @title LearningModule — BAP-578 Proof of Prompt (PoP) implementation
/// @notice Validates and records agent learning history as Merkle Tree roots.
/// @dev Data stored on AgentNFA; this contract holds only validation logic.
///      Upgradeable via AgentNFA.setLearningModule(newAddress).
contract LearningModule is ILearningModule {
    /// @notice The AgentNFA contract
    IAgentNFALearning public immutable agentNFA;

    constructor(address _agentNFA) {
        if (_agentNFA == address(0)) revert Errors.ZeroAddress();
        agentNFA = IAgentNFALearning(_agentNFA);
    }

    /// @notice Toggle learning — delegates to AgentNFA.setLearningEnabled
    /// @dev Owner can also call AgentNFA.setLearningEnabled directly
    function enableLearning(uint256 tokenId, bool enabled) external override {
        if (msg.sender != agentNFA.ownerOf(tokenId)) revert Errors.OnlyOwner();
        agentNFA.setLearningEnabled(tokenId, enabled);
        emit LearningStateChanged(tokenId, enabled);
    }

    /// @notice Append a single PoP leaf (only operator, learning must be enabled)
    /// @dev In V4.0, newLeafHash is emitted for off-chain tracing only.
    ///      newRoot is TRUSTED from the operator without on-chain verification.
    ///      Future: verify(oldRoot, newLeafHash, proof) == newRoot.
    function appendLearning(
        uint256 tokenId,
        bytes32,
        bytes32 newRoot
    ) external override {
        _checkOperator(tokenId);
        if (!agentNFA.learningEnabled(tokenId))
            revert Errors.AgentPaused(tokenId);
        uint256 currentCount = agentNFA.learningLeafCount(tokenId);
        agentNFA.setLearningData(tokenId, newRoot, currentCount + 1);
        emit LearningRootUpdated(tokenId, newRoot, currentCount + 1);
    }

    /// @notice Batch append multiple PoP leaves (only operator, learning must be enabled)
    function batchAppendLearning(
        uint256 tokenId,
        bytes32[] calldata leafHashes,
        bytes32 newRoot
    ) external override {
        _checkOperator(tokenId);
        if (!agentNFA.learningEnabled(tokenId))
            revert Errors.AgentPaused(tokenId);
        if (leafHashes.length == 0) revert Errors.InvalidInitParams();
        uint256 currentCount = agentNFA.learningLeafCount(tokenId);
        uint256 newCount = currentCount + leafHashes.length;
        agentNFA.setLearningData(tokenId, newRoot, newCount);
        emit LearningRootUpdated(tokenId, newRoot, newCount);
    }

    /// @notice Get learning metrics from AgentNFA
    function getLearningMetrics(
        uint256 tokenId
    )
        external
        view
        override
        returns (bool isEnabled, bytes32 currentRoot, uint256 totalLeaves)
    {
        isEnabled = agentNFA.learningEnabled(tokenId);
        currentRoot = agentNFA.learningTreeRoot(tokenId);
        totalLeaves = agentNFA.learningLeafCount(tokenId);
    }

    /// @dev Only the operator (Runner) can write learning data
    function _checkOperator(uint256 tokenId) internal view {
        address operator = agentNFA.operatorOf(tokenId);
        if (operator == address(0) || msg.sender != operator) {
            revert Errors.Unauthorized();
        }
    }
}
