// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    IERC721
} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {ILearningModule} from "./interfaces/ILearningModule.sol";
import {IMemoryModuleRegistry} from "./interfaces/IMemoryModuleRegistry.sol";
import {IERC4907} from "./interfaces/IERC4907.sol";

/// @title AgentNFAExtensions
/// @notice External storage for AgentNFA features removed due to EIP-170 limits
/// @dev Implements BAP-578 LearningModule and MemoryRegistry
contract AgentNFAExtensions is ILearningModule, IMemoryModuleRegistry {
    address public immutable agentNFA;

    // --- State ---
    mapping(uint256 => bool) public learningEnabled;
    mapping(uint256 => bytes32) public learningRoot;
    mapping(uint256 => address) public memoryRegistry;

    // --- Errors ---
    error NotOwnerOrRenter();
    error NotOwner();

    constructor(address _agentNFA) {
        require(_agentNFA != address(0), "Zero address NFA");
        agentNFA = _agentNFA;
    }

    // --- Access Control ---
    function _requireOwnerOrRenter(uint256 tokenId) internal view {
        address owner = IERC721(agentNFA).ownerOf(tokenId);
        address renter = IERC4907(agentNFA).userOf(tokenId);
        if (msg.sender != owner && msg.sender != renter) {
            revert NotOwnerOrRenter();
        }
    }

    function _requireOwner(uint256 tokenId) internal view {
        address owner = IERC721(agentNFA).ownerOf(tokenId);
        if (msg.sender != owner) {
            revert NotOwner();
        }
    }

    // --- ILearningModule ---
    function enableLearning(uint256 tokenId, bool enabled) external override {
        _requireOwnerOrRenter(tokenId);
        learningEnabled[tokenId] = enabled;
        emit LearningStateChanged(tokenId, enabled);
    }

    function updateLearningRoot(
        uint256 tokenId,
        bytes32 newRoot
    ) external override {
        // Typically updated dynamically by the agent runner or owner
        _requireOwnerOrRenter(tokenId);
        learningRoot[tokenId] = newRoot;
        emit LearningRootUpdated(tokenId, newRoot);
    }

    function getLearningMetrics(
        uint256 tokenId
    ) external view override returns (bool isEnabled, bytes32 currentRoot) {
        return (learningEnabled[tokenId], learningRoot[tokenId]);
    }

    // --- IMemoryModuleRegistry ---
    function setMemoryRegistry(
        uint256 tokenId,
        address registryAddress
    ) external override {
        // Setting registry is an ownership level action
        _requireOwner(tokenId);
        memoryRegistry[tokenId] = registryAddress;
        emit MemoryRegistrySet(tokenId, registryAddress);
    }

    function getMemoryModules(
        uint256 tokenId
    ) external view override returns (address registryAddress) {
        return memoryRegistry[tokenId];
    }
}
