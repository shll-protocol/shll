// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ILearningModule
/// @notice Interface for BAP-578 Learning Module (V3.2 Extension)
interface ILearningModule {
    /// @notice Emit when learning is enabled or disabled
    event LearningStateChanged(uint256 indexed tokenId, bool enabled);
    /// @notice Emit when learning root hash is updated
    event LearningRootUpdated(uint256 indexed tokenId, bytes32 newRoot);

    /// @notice Toggle learning capabilities for an agent
    /// @param tokenId The agent token ID
    /// @param enabled True to enable, false to disable
    function enableLearning(uint256 tokenId, bool enabled) external;

    /// @notice Update the learning root hash (e.g. Merkle root of experiences)
    /// @param tokenId The agent token ID
    /// @param newRoot The new learning root hash
    function updateLearningRoot(uint256 tokenId, bytes32 newRoot) external;

    /// @notice Get learning metrics/state
    /// @param tokenId The agent token ID
    /// @return isEnabled Whether learning is enabled
    /// @return currentRoot Current learning root hash
    function getLearningMetrics(
        uint256 tokenId
    ) external view returns (bool isEnabled, bytes32 currentRoot);
}
