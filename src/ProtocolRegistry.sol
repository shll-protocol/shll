// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    Ownable2Step,
    Ownable
} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";

/// @title ProtocolRegistry — Unified DeFi protocol registration
/// @notice One-tx registration/removal across ReceiverGuardPolicyV2,
///         DeFiGuardPolicyV2, and SpendingLimitPolicyV2.
/// @dev After deployment, PolicyGuardV4.transferOwnership(registry) must be
///      called so that Registry can invoke policy admin functions (which check
///      `Ownable(guard).owner() == msg.sender`).
///
///      IMPORTANT: ReceiverGuardPolicyV2 has hardcoded PancakeSwap patterns in
///      its constructor. Those are NOT managed by this Registry. removeProtocol()
///      cannot undo constructor-hardcoded patterns.
///
///      emergencyCall() can target ANY address (not restricted to known policies).
///      This is intentional for maximum flexibility but requires trusting the owner.
contract ProtocolRegistry is Ownable2Step {
    // ═══════════════════════════════════════════════════════
    //                       TYPES
    // ═══════════════════════════════════════════════════════

    struct ProtocolConfig {
        string name;
        bytes4[] allSelectors; // DeFiGuard: addSelector
        bytes4[] buySelectors; // ReceiverGuard: setPatternBatch
        uint8 receiverPattern; // ReceiverGuard decode pattern (0-5)
        address[] targets; // DeFiGuard: addGlobalTarget + SpendingLimit: setApprovedSpender
        bool active;
    }

    // ═══════════════════════════════════════════════════════
    //                       STORAGE
    // ═══════════════════════════════════════════════════════

    IReceiverGuardV2 public immutable receiverGuard;
    IDeFiGuardV2 public immutable defiGuard;
    ISpendingLimitV2 public immutable spendingLimit;
    address public immutable policyGuard; // PolicyGuardV4

    mapping(bytes32 => ProtocolConfig) internal _protocols;
    bytes32[] public protocolIds;

    // Reference counts: prevent remove from breaking shared selectors/targets
    mapping(bytes4 => uint256) public selectorRefCount;
    mapping(address => uint256) public targetRefCount;
    mapping(bytes4 => uint256) public buySelectorRefCount;
    mapping(bytes4 => uint8) public buySelectorPattern;

    // Track whether an entry was introduced by Registry itself.
    // If a value already existed before Registry registration, removeProtocol()
    // must not remove it when refCount drops to zero.
    mapping(bytes4 => bool) public managedSelector;
    mapping(address => bool) public managedGlobalTarget;
    mapping(address => bool) public managedApprovedSpender;
    mapping(bytes4 => bool) public managedBuySelector;

    // ═══════════════════════════════════════════════════════
    //                       EVENTS
    // ═══════════════════════════════════════════════════════

    event ProtocolRegistered(
        bytes32 indexed protocolId,
        string name,
        uint256 selectorCount,
        uint256 targetCount
    );
    event ProtocolRemoved(bytes32 indexed protocolId, string name);
    event EmergencyCallExecuted(address indexed target, bool success);

    // ═══════════════════════════════════════════════════════
    //                       ERRORS
    // ═══════════════════════════════════════════════════════

    error ProtocolAlreadyExists(bytes32 id);
    error ProtocolNotFound(bytes32 id);
    error EmergencyCallFailed(bytes returnData);
    error GuardCallFailed(bytes returnData);
    error ZeroAddress();
    error InvalidReceiverPattern();
    error BuySelectorPatternMismatch(
        bytes4 selector,
        uint8 existingPattern,
        uint8 requestedPattern
    );

    // ═══════════════════════════════════════════════════════
    //                     CONSTRUCTOR
    // ═══════════════════════════════════════════════════════

    /// @param _receiverGuard ReceiverGuardPolicyV2 address
    /// @param _defiGuard DeFiGuardPolicyV2 address
    /// @param _spendingLimit SpendingLimitPolicyV2 address
    /// @param _policyGuard PolicyGuardV4 address
    constructor(
        address _receiverGuard,
        address _defiGuard,
        address _spendingLimit,
        address _policyGuard
    ) {
        if (_receiverGuard == address(0)) revert ZeroAddress();
        if (_defiGuard == address(0)) revert ZeroAddress();
        if (_spendingLimit == address(0)) revert ZeroAddress();
        if (_policyGuard == address(0)) revert ZeroAddress();

        receiverGuard = IReceiverGuardV2(_receiverGuard);
        defiGuard = IDeFiGuardV2(_defiGuard);
        spendingLimit = ISpendingLimitV2(_spendingLimit);
        policyGuard = _policyGuard;
    }

    // ═══════════════════════════════════════════════════════
    //              CORE: Register / Remove
    // ═══════════════════════════════════════════════════════

    /// @notice Register a DeFi protocol across all 3 policies in one tx
    /// @param id Protocol identifier (e.g. keccak256("PANCAKESWAP_V2"))
    /// @param config Protocol configuration
    function registerProtocol(
        bytes32 id,
        ProtocolConfig calldata config
    ) external onlyOwner {
        if (_protocols[id].active) revert ProtocolAlreadyExists(id);

        // 1. ReceiverGuard: register buy selectors with decode pattern
        if (config.buySelectors.length > 0) {
            if (!_isValidReceiverPattern(config.receiverPattern)) {
                revert InvalidReceiverPattern();
            }

            bytes4[] memory selectorsToSet = new bytes4[](
                config.buySelectors.length
            );
            uint256 setCount = 0;

            for (uint256 i = 0; i < config.buySelectors.length; i++) {
                bytes4 sel = config.buySelectors[i];

                bool dup = false;
                for (uint256 j = 0; j < i; j++) {
                    if (config.buySelectors[j] == sel) {
                        dup = true;
                        break;
                    }
                }
                if (dup) continue;

                uint256 ref = buySelectorRefCount[sel];
                if (ref == 0) {
                    uint8 currentPattern = receiverGuard.selectorPattern(sel);
                    if (currentPattern != 0) {
                        if (currentPattern != config.receiverPattern) {
                            revert BuySelectorPatternMismatch(
                                sel,
                                currentPattern,
                                config.receiverPattern
                            );
                        }
                        buySelectorPattern[sel] = currentPattern;
                    } else {
                        buySelectorPattern[sel] = config.receiverPattern;
                        managedBuySelector[sel] = true;
                        selectorsToSet[setCount++] = sel;
                    }
                    buySelectorRefCount[sel] = 1;
                } else {
                    uint8 existingPattern = buySelectorPattern[sel];
                    if (existingPattern != config.receiverPattern) {
                        revert BuySelectorPatternMismatch(
                            sel,
                            existingPattern,
                            config.receiverPattern
                        );
                    }
                    buySelectorRefCount[sel] = ref + 1;
                }
            }

            if (setCount > 0) {
                bytes4[] memory uniqueSelectors = new bytes4[](setCount);
                for (uint256 i = 0; i < setCount; i++) {
                    uniqueSelectors[i] = selectorsToSet[i];
                }
                receiverGuard.setPatternBatch(
                    uniqueSelectors,
                    config.receiverPattern
                );
            }
        }

        // 2. DeFiGuard: add selectors to global whitelist (ref-counted, skip dupes)
        for (uint256 i = 0; i < config.allSelectors.length; i++) {
            bytes4 sel = config.allSelectors[i];
            bool dup = false;
            for (uint256 j = 0; j < i; j++) {
                if (config.allSelectors[j] == sel) {
                    dup = true;
                    break;
                }
            }
            if (dup) continue;
            uint256 ref = selectorRefCount[sel];
            if (ref == 0) {
                if (!defiGuard.allowedSelectors(sel)) {
                    defiGuard.addSelector(sel);
                    managedSelector[sel] = true;
                }
                selectorRefCount[sel] = 1;
            } else {
                selectorRefCount[sel] = ref + 1;
            }
        }

        // DeFiGuard + SpendingLimit: add targets (ref-counted, skip dupes)
        for (uint256 i = 0; i < config.targets.length; i++) {
            address target = config.targets[i];
            bool dup = false;
            for (uint256 j = 0; j < i; j++) {
                if (config.targets[j] == target) {
                    dup = true;
                    break;
                }
            }
            if (dup) continue;
            uint256 ref = targetRefCount[target];
            if (ref == 0) {
                if (!defiGuard.globalAllowed(target)) {
                    defiGuard.addGlobalTarget(target);
                    managedGlobalTarget[target] = true;
                }
                if (!spendingLimit.approvedSpender(target)) {
                    spendingLimit.setApprovedSpender(target, true);
                    managedApprovedSpender[target] = true;
                }
                targetRefCount[target] = 1;
            } else {
                targetRefCount[target] = ref + 1;
            }
        }

        // 3. Store on-chain
        ProtocolConfig storage p = _protocols[id];
        p.name = config.name;
        p.receiverPattern = config.receiverPattern;
        p.active = true;

        for (uint256 i = 0; i < config.allSelectors.length; i++) {
            p.allSelectors.push(config.allSelectors[i]);
        }
        for (uint256 i = 0; i < config.buySelectors.length; i++) {
            p.buySelectors.push(config.buySelectors[i]);
        }
        for (uint256 i = 0; i < config.targets.length; i++) {
            p.targets.push(config.targets[i]);
        }

        protocolIds.push(id);

        emit ProtocolRegistered(
            id,
            config.name,
            config.allSelectors.length,
            config.targets.length
        );
    }

    /// @notice Remove a protocol from all 3 policies in one tx
    /// @param id Protocol identifier
    function removeProtocol(bytes32 id) external onlyOwner {
        ProtocolConfig storage p = _protocols[id];
        if (!p.active) revert ProtocolNotFound(id);

        // Cache name before delete
        string memory name = p.name;

        // 1. ReceiverGuard: zero out buy selector patterns (ref-counted, skip dupes)
        for (uint256 i = 0; i < p.buySelectors.length; i++) {
            bytes4 sel = p.buySelectors[i];
            bool dup = false;
            for (uint256 j = 0; j < i; j++) {
                if (p.buySelectors[j] == sel) {
                    dup = true;
                    break;
                }
            }
            if (dup) continue;

            if (buySelectorRefCount[sel] > 0) {
                buySelectorRefCount[sel]--;
            }
            if (buySelectorRefCount[sel] == 0) {
                delete buySelectorPattern[sel];
                if (managedBuySelector[sel]) {
                    receiverGuard.setPattern(sel, 0);
                    delete managedBuySelector[sel];
                }
            }
        }

        // 2. DeFiGuard: remove selectors (only if refCount drops to 0, skip dupes)
        for (uint256 i = 0; i < p.allSelectors.length; i++) {
            bytes4 sel = p.allSelectors[i];
            bool dup = false;
            for (uint256 j = 0; j < i; j++) {
                if (p.allSelectors[j] == sel) {
                    dup = true;
                    break;
                }
            }
            if (dup) continue;
            if (selectorRefCount[sel] > 0) {
                selectorRefCount[sel]--;
            }
            if (selectorRefCount[sel] == 0) {
                if (managedSelector[sel]) {
                    if (defiGuard.allowedSelectors(sel)) {
                        defiGuard.removeSelector(sel);
                    }
                    delete managedSelector[sel];
                }
            }
        }

        // 3. DeFiGuard + SpendingLimit: remove targets (only if refCount drops to 0, skip dupes)
        for (uint256 i = 0; i < p.targets.length; i++) {
            address target = p.targets[i];
            bool dup = false;
            for (uint256 j = 0; j < i; j++) {
                if (p.targets[j] == target) {
                    dup = true;
                    break;
                }
            }
            if (dup) continue;
            if (targetRefCount[target] > 0) {
                targetRefCount[target]--;
            }
            if (targetRefCount[target] == 0) {
                if (managedGlobalTarget[target]) {
                    if (defiGuard.globalAllowed(target)) {
                        defiGuard.removeGlobalTarget(target);
                    }
                    delete managedGlobalTarget[target];
                }
                if (managedApprovedSpender[target]) {
                    if (spendingLimit.approvedSpender(target)) {
                        spendingLimit.setApprovedSpender(target, false);
                    }
                    delete managedApprovedSpender[target];
                }
            }
        }

        // 4. Clean up storage completely (prevents C-2: re-registration data corruption)
        delete _protocols[id];

        // Remove from protocolIds array (swap-and-pop)
        for (uint256 i = 0; i < protocolIds.length; i++) {
            if (protocolIds[i] == id) {
                protocolIds[i] = protocolIds[protocolIds.length - 1];
                protocolIds.pop();
                break;
            }
        }

        emit ProtocolRemoved(id, name);
    }

    // ═══════════════════════════════════════════════════════
    //                  EMERGENCY / PROXY
    // ═══════════════════════════════════════════════════════

    /// @notice Emergency: call any policy function directly
    /// @dev WARNING: Can target any address. Use with extreme caution.
    ///      Example scenarios: calling setOutputPattern on SpendingLimitV2,
    ///      managing blacklists on DeFiGuardV2, etc.
    /// @param target The policy contract to call
    /// @param data The encoded function call
    function emergencyCall(
        address target,
        bytes calldata data
    ) external onlyOwner returns (bytes memory) {
        (bool success, bytes memory returnData) = target.call(data);
        if (!success) revert EmergencyCallFailed(returnData);
        emit EmergencyCallExecuted(target, success);
        return returnData;
    }

    /// @notice Proxy a call to PolicyGuardV4 (onlyOwner functions)
    /// @dev Since Registry owns PolicyGuardV4, this allows the deployer to
    ///      still manage templates, approve policies, etc. through Registry.
    /// @param data The encoded PolicyGuardV4 function call
    function guardCall(
        bytes calldata data
    ) external onlyOwner returns (bytes memory) {
        (bool success, bytes memory returnData) = policyGuard.call(data);
        if (!success) revert GuardCallFailed(returnData);
        return returnData;
    }

    // ═══════════════════════════════════════════════════════
    //              PolicyGuardV4 OWNERSHIP
    // ═══════════════════════════════════════════════════════

    /// @notice Accept ownership of PolicyGuardV4 (Ownable2Step)
    /// @dev Call after PolicyGuardV4.transferOwnership(address(registry))
    function acceptGuardOwnership() external onlyOwner {
        Ownable2Step(policyGuard).acceptOwnership();
    }

    // ═══════════════════════════════════════════════════════
    //                       VIEWS
    // ═══════════════════════════════════════════════════════

    /// @notice Get protocol details
    function getProtocol(
        bytes32 id
    ) external view returns (ProtocolConfig memory) {
        return _protocols[id];
    }

    /// @notice List all active protocol IDs
    function listProtocols() external view returns (bytes32[] memory) {
        return protocolIds;
    }

    /// @notice Get the number of registered protocols
    function protocolCount() external view returns (uint256) {
        return protocolIds.length;
    }

    /// @dev 1-4 are concrete decode patterns in ReceiverGuardPolicyV2.
    ///      5 is an explicit pass-through mode used by some integrations.
    function _isValidReceiverPattern(uint8 pattern) internal pure returns (bool) {
        return pattern >= 1 && pattern <= 5;
    }
}

// ═══════════════════════════════════════════════════════
//              MINIMAL INTERFACES
// ═══════════════════════════════════════════════════════

interface IReceiverGuardV2 {
    function setPattern(bytes4 selector, uint8 pattern) external;
    function setPatternBatch(
        bytes4[] calldata selectors,
        uint8 pattern
    ) external;
    function selectorPattern(bytes4) external view returns (uint8);
}

interface IDeFiGuardV2 {
    function addSelector(bytes4 selector) external;
    function removeSelector(bytes4 selector) external;
    function addGlobalTarget(address target) external;
    function removeGlobalTarget(address target) external;
    function allowedSelectors(bytes4) external view returns (bool);
    function globalAllowed(address) external view returns (bool);
}

interface ISpendingLimitV2 {
    function setApprovedSpender(address spender, bool allowed) external;
    function approvedSpender(address) external view returns (bool);
}
