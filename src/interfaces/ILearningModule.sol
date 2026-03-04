// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ILearningModule — BAP-578 Learning Module interface
/// @notice Manages Proof of Prompt (PoP) Merkle Tree for agent learning history.
/// @dev Data (roots, counts) stored on AgentNFA; this module holds only logic.
///      Upgradeable via AgentNFA.setLearningModule(newAddress).
interface ILearningModule {
    // ─── Events ───
    event LearningStateChanged(uint256 indexed tokenId, bool enabled);
    event LearningRootUpdated(
        uint256 indexed tokenId,
        bytes32 newRoot,
        uint256 leafCount
    );

    /// @notice Toggle learning capabilities for an agent
    /// @param tokenId The agent token ID
    /// @param enabled True to enable, false to disable
    function enableLearning(uint256 tokenId, bool enabled) external;

    /// @notice Append a single PoP leaf and update the Merkle root
    /// @param tokenId The agent token ID
    /// @param newLeafHash Hash of the new learning record (keccak256(prompt + response))
    /// @param newRoot The new Merkle root after appending
    function appendLearning(
        uint256 tokenId,
        bytes32 newLeafHash,
        bytes32 newRoot
    ) external;

    /// @notice Batch append multiple PoP leaves (gas optimization)
    /// @param tokenId The agent token ID
    /// @param leafHashes Array of leaf hashes
    /// @param newRoot The new Merkle root after batch append
    function batchAppendLearning(
        uint256 tokenId,
        bytes32[] calldata leafHashes,
        bytes32 newRoot
    ) external;

    /// @notice Get learning metrics/state
    /// @param tokenId The agent token ID
    /// @return isEnabled Whether learning is enabled
    /// @return currentRoot Current learning root hash
    /// @return totalLeaves Total number of PoP leaves recorded
    function getLearningMetrics(
        uint256 tokenId
    )
        external
        view
        returns (bool isEnabled, bytes32 currentRoot, uint256 totalLeaves);
}
