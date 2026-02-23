// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IMemoryModuleRegistry
/// @notice Interface for BAP-578 Memory Module Registry (V3.2 Extension)
interface IMemoryModuleRegistry {
    /// @notice Emit when memory registry is updated for an agent
    event MemoryRegistrySet(uint256 indexed tokenId, address registryAddress);

    /// @notice Set the memory registry contract address for an agent
    /// @param tokenId The agent token ID
    /// @param registryAddress The address of the memory registry/manager
    function setMemoryRegistry(
        uint256 tokenId,
        address registryAddress
    ) external;

    /// @notice Get the memory module registry assigned to an agent
    /// @param tokenId The agent token ID
    /// @return registryAddress The configured memory registry address
    function getMemoryModules(
        uint256 tokenId
    ) external view returns (address registryAddress);
}
