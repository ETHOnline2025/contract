// SPDX-License-Identifier: EVVM-NONCOMMERCIAL-1.0
// Full license terms available at: https://www.evvm.info/docs/EVVMNoncommercialLicense

pragma solidity ^0.8.0;

import {EvvmStructs} from "./EvvmStructs.sol";

/**
 * @title EvvmStorage
 * @author jistro.eth
 * @dev Storage layout contract for EVVM proxy pattern implementation with chain-agnostic support.
 *      This contract inherits all structures from EvvmStructs and
 *      defines the storage layout that will be used by the proxy pattern.
 *
 * @notice This contract should not be deployed directly, it's meant to be
 *         inherited by the implementation contracts to ensure they maintain
 *         the same storage layout.
 *
 * @custom:chain-agnostic Added mappings for chain-agnostic identifiers to enable
 *         cross-chain account identification while maintaining EVM core functionality
 */
abstract contract EvvmStorage is EvvmStructs {
    address constant ETH_ADDRESS = address(0);
    bytes1 constant FLAG_IS_STAKER = 0x01;

    address nameServiceAddress;

    address stakingContractAddress;

    address treasuryAddress;

    /// @notice Address of the authorized trading contract that can modify balances
    address authorizedTradingContract;

    address whitelistTokenToBeAdded_address;
    address whitelistTokenToBeAdded_pool;
    uint256 whitelistTokenToBeAdded_dateToSet;

    /**
     * @dev The address of the implementation contract is stored
     *      separately because of the way the proxy pattern works,
     *      rather than in a struct.
     */
    address currentImplementation;
    address proposalImplementation;
    uint256 timeToAcceptImplementation;

    uint256 windowTimeToChangeEvvmID;

    EvvmMetadata evvmMetadata;

    AddressTypeProposal admin;

    bytes1 breakerSetupNameServiceAddress;

    mapping(address => bytes1) stakerList;

    // ═════════════════════════════════════════════════════════════════════════════════════════════
    // EVM NATIVE BALANCES (for EVM-to-EVM operations)
    // ═════════════════════════════════════════════════════════════════════════════════════════════

    /// @notice EVM-native balance storage for address-based operations
    mapping(address user => mapping(address token => uint256 quantity)) balances;

    mapping(address user => uint256 nonce) nextSyncUsedNonce;

    mapping(address user => mapping(uint256 nonce => bool isUsed)) asyncUsedNonce;

    mapping(address user => uint256 nonce) nextFisherDepositNonce;

    // ═════════════════════════════════════════════════════════════════════════════════════════════
    // CAIP-10 NATIVE BALANCES (for chain-agnostic operations)
    // ═════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Chain-agnostic balance storage using raw CAIP-10 identifiers
     * @dev Parallel balance system to EVM balances for non-EVM chain support
     *      Example: caip10Balances["cosmos:cosmoshub-4:cosmos1abc"]["cosmos:cosmoshub-4:uatom"] = 1000
     *      This is separate from the EVM address-based balances system
     */
    mapping(string caip10User => mapping(string caip10Token => uint256 quantity)) caip10Balances;

    /**
     * @notice Nonce tracking for CAIP-10 identified users (synchronous)
     * @dev Parallel to nextSyncUsedNonce for chain-agnostic operations
     */
    mapping(string caip10User => uint256 nonce) caip10NextSyncUsedNonce;

    /**
     * @notice Nonce tracking for CAIP-10 identified users (asynchronous)
     * @dev Parallel to asyncUsedNonce for chain-agnostic operations
     */
    mapping(string caip10User => mapping(uint256 nonce => bool isUsed)) caip10AsyncUsedNonce;

    // ═════════════════════════════════════════════════════════════════════════════════════════════
    // CAIP-10 IDENTITY MAPPING LAYER (for EVM interoperability)
    // ═════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Maps CAIP-10 identifiers to their corresponding EVM addresses
     * @dev Enables cross-chain account identification and lookups
     *      Example: "eip155:1:0x1234..." => 0x1234...
     *               "cosmos:cosmoshub-4:cosmos1abc..." => 0x5678... (mapped representative)
     */
    mapping(string caip10Id => address evmAddress) caip10ToAddress;

    /**
     * @notice Maps EVM addresses to their primary CAIP-10 identifier
     * @dev Reverse lookup for address-to-identifier resolution
     *      Used when converting EVM operations back to CAIP-10 format
     */
    mapping(address evmAddress => string caip10Id) addressToCaip10;

    /**
     * @notice Tracks whether a CAIP-10 identifier has been registered
     * @dev Used for validation and preventing duplicate registrations
     */
    mapping(string caip10Id => bool isRegistered) caip10Registered;

    /**
     * @notice Maps non-EVM CAIP-10 identifiers to synthetic EVM addresses
     * @dev For chains like Cosmos, Bitcoin, Solana, we generate deterministic EVM addresses
     *      to enable them to interact with the EVM-based core system
     *      Example: "cosmos:cosmoshub-4:cosmos1abc..." => synthetic address derived from hash
     */
    mapping(string nonEvmCaip10Id => address syntheticAddress) nonEvmToSyntheticAddress;
}
