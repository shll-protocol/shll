// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IERC8004IdentityRegistry — ERC-8004 Identity Registry interface
/// @notice Minimal interface for agent registration and management
/// @dev See https://eips.ethereum.org/EIPS/eip-8004
interface IERC8004IdentityRegistry {
    struct MetadataEntry {
        string metadataKey;
        bytes metadataValue;
    }

    /// @notice Register a new agent with a URI pointing to the registration file
    /// @param agentURI URI of the agent registration file (IPFS/HTTPS/data URI)
    /// @return agentId The registry-assigned agent ID (ERC-721 tokenId)
    function register(
        string calldata agentURI
    ) external returns (uint256 agentId);

    /// @notice Register a new agent with URI and on-chain metadata
    /// @param agentURI URI of the agent registration file
    /// @param metadata Array of key-value metadata entries
    /// @return agentId The registry-assigned agent ID
    function register(
        string calldata agentURI,
        MetadataEntry[] calldata metadata
    ) external returns (uint256 agentId);

    /// @notice Update an agent's registration URI
    /// @param agentId The agent ID to update
    /// @param newURI The new registration file URI
    function setAgentURI(uint256 agentId, string calldata newURI) external;

    /// @notice Set the agent's payment wallet (requires EIP-712/ERC-1271 proof)
    /// @param agentId The agent ID
    /// @param newWallet The new wallet address
    /// @param deadline Signature validity deadline
    /// @param signature EIP-712 or ERC-1271 signature proving wallet control
    function setAgentWallet(
        uint256 agentId,
        address newWallet,
        uint256 deadline,
        bytes calldata signature
    ) external;

    /// @notice Get the agent's payment wallet address
    /// @param agentId The agent ID
    /// @return The wallet address
    function getAgentWallet(uint256 agentId) external view returns (address);
}
