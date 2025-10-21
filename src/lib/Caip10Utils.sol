// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;

/**
 * @title Caip10Utils
 * @author EVVM Team
 * @notice Chain-agnostic utility library for CAIP-10 identifier parsing and validation
 * @dev Provides comprehensive support for CAIP-10 account identifiers across multiple blockchain namespaces
 *
 * CAIP-10 Format: namespace:chainId:accountAddress
 * Examples:
 * - EVM: "eip155:1:0x1234567890123456789012345678901234567890"
 * - Cosmos: "cosmos:cosmoshub-4:cosmos1abc123def456ghi789jkl0"
 * - Bitcoin: "bip122:000000000019d6689c085ae165831e93:128Lkh3S7CkDTBZ8W7BbpsN3YYizJMp8p6"
 * - Solana: "solana:mainnet:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp"
 *
 * @custom:security This library does NOT validate semantic correctness of addresses (checksums, etc.)
 * @custom:chain-support Supports EVM (eip155), Cosmos (cosmos), Bitcoin (bip122), Solana (solana), and generic namespaces
 */
library Caip10Utils {
    // ═════════════════════════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═════════════════════════════════════════════════════════════════════════════════════════════

    /// @notice Thrown when CAIP-10 format is invalid or malformed
    error InvalidCaip10Format();

    /// @notice Thrown when chain namespace is not recognized or supported
    error InvalidChainNamespace();

    /// @notice Thrown when address format doesn't match expected format for the chain
    error InvalidAddress();

    /// @notice Thrown when attempting EVM-specific operations on non-EVM chains
    error NotEvmChain();

    // ═════════════════════════════════════════════════════════════════════════════════════════════
    // CORE PARSING FUNCTIONS
    // ═════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Parses a CAIP-10 identifier into its constituent parts
     * @dev Splits the identifier by colons and validates basic structure
     * @param caip10 The complete CAIP-10 identifier string
     * @return namespace The blockchain namespace (e.g., "eip155", "cosmos", "bip122")
     * @return chainId The specific chain identifier within the namespace
     * @return accountAddress The account address in the chain's native format
     */
    function parseCaip10(string memory caip10)
        internal
        pure
        returns (string memory namespace, string memory chainId, string memory accountAddress)
    {
        bytes memory caip10Bytes = bytes(caip10);
        if (caip10Bytes.length == 0) revert InvalidCaip10Format();

        uint256 firstColon = 0;
        uint256 secondColon = 0;

        for (uint256 i = 0; i < caip10Bytes.length; i++) {
            if (caip10Bytes[i] == ":") {
                if (firstColon == 0) {
                    firstColon = i;
                } else if (secondColon == 0) {
                    secondColon = i;
                    break;
                }
            }
        }

        if (firstColon == 0 || secondColon == 0) revert InvalidCaip10Format();

        namespace = substring(caip10, 0, firstColon);
        chainId = substring(caip10, firstColon + 1, secondColon);
        accountAddress = substring(caip10, secondColon + 1, caip10Bytes.length);
    }

    /**
     * @notice Extracts the namespace from a CAIP-10 identifier
     * @dev Returns only the first part before the first colon
     * @param caip10 The complete CAIP-10 identifier string
     * @return The blockchain namespace
     */
    function extractNamespace(string memory caip10) internal pure returns (string memory) {
        (string memory namespace,,) = parseCaip10(caip10);
        return namespace;
    }

    /**
     * @notice Extracts the chain ID from a CAIP-10 identifier
     * @dev Returns only the middle part between the first and second colons
     * @param caip10 The complete CAIP-10 identifier string
     * @return The chain identifier
     */
    function extractChainId(string memory caip10) internal pure returns (string memory) {
        (, string memory chainId,) = parseCaip10(caip10);
        return chainId;
    }

    /**
     * @notice Extracts the account address from a CAIP-10 identifier
     * @dev Returns only the address part after the second colon
     * @param caip10 The complete CAIP-10 identifier string
     * @return The account address in chain-native format
     */
    function extractAccountAddress(string memory caip10) internal pure returns (string memory) {
        (,, string memory accountAddress) = parseCaip10(caip10);
        return accountAddress;
    }

    // ═════════════════════════════════════════════════════════════════════════════════════════════
    // EVM-SPECIFIC FUNCTIONS
    // ═════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Extracts an EVM address from a CAIP-10 identifier
     * @dev ONLY works with eip155 (EVM) namespaces. Reverts for non-EVM chains.
     * @param caip10 The complete CAIP-10 identifier (must be eip155 namespace)
     * @return The extracted Ethereum address
     */
    function extractAddress(string memory caip10) internal pure returns (address) {
        (string memory namespace,, string memory accountAddress) = parseCaip10(caip10);

        // Verify this is an EVM chain
        if (!isEvmNamespace(namespace)) revert NotEvmChain();

        return parseEvmAddress(accountAddress);
    }

    /**
     * @notice Parses a hex string into an Ethereum address
     * @dev Expects "0x" prefix followed by 40 hexadecimal characters
     * @param addressStr The address string to parse (e.g., "0x1234...7890")
     * @return The parsed Ethereum address
     */
    function parseEvmAddress(string memory addressStr) public pure returns (address) {
        bytes memory addressBytes = bytes(addressStr);
        if (addressBytes.length != 42) revert InvalidAddress();
        if (addressBytes[0] != "0" || addressBytes[1] != "x") revert InvalidAddress();

        uint160 addr = 0;
        for (uint256 i = 2; i < 42; i++) {
            uint8 digit = uint8(addressBytes[i]);
            uint8 value;

            if (digit >= 48 && digit <= 57) {
                value = digit - 48;
            } else if (digit >= 65 && digit <= 70) {
                value = digit - 55;
            } else if (digit >= 97 && digit <= 102) {
                value = digit - 87;
            } else {
                revert InvalidAddress();
            }

            addr = addr * 16 + value;
        }

        return address(addr);
    }

    /**
     * @notice Creates a CAIP-10 identifier from namespace, chain ID, and EVM address
     * @dev Convenience function for EVM chains
     * @param namespace The blockchain namespace (should be "eip155" for EVM)
     * @param chainId The EVM chain ID as a string (e.g., "1" for Ethereum mainnet)
     * @param account The Ethereum address
     * @return The complete CAIP-10 identifier
     */
    function toCaip10(string memory namespace, string memory chainId, address account)
        internal
        pure
        returns (string memory)
    {
        return string(abi.encodePacked(namespace, ":", chainId, ":", toHexString(account)));
    }

    /**
     * @notice Converts an Ethereum address to a hex string with "0x" prefix
     * @dev Produces lowercase hex representation
     * @param account The Ethereum address to convert
     * @return The hex string representation (42 characters including "0x")
     */
    function toHexString(address account) internal pure returns (string memory) {
        bytes memory hexChars = "0123456789abcdef";
        bytes memory result = new bytes(42);
        result[0] = "0";
        result[1] = "x";

        uint160 value = uint160(account);
        for (uint256 i = 41; i > 1; i--) {
            result[i] = hexChars[value & 0xf];
            value >>= 4;
        }

        return string(result);
    }

    // ═════════════════════════════════════════════════════════════════════════════════════════════
    // VALIDATION FUNCTIONS
    // ═════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Validates that a string conforms to CAIP-10 format
     * @dev Checks for presence of at least 2 colons (minimum structure)
     * @param caip10 The string to validate
     * @return true if the string has valid CAIP-10 structure, false otherwise
     */
    function validateCaip10(string memory caip10) internal pure returns (bool) {
        bytes memory caip10Bytes = bytes(caip10);
        if (caip10Bytes.length == 0) return false;

        uint256 colonCount = 0;
        for (uint256 i = 0; i < caip10Bytes.length; i++) {
            if (caip10Bytes[i] == ":") {
                colonCount++;
            }
        }

        return colonCount >= 2;
    }

    /**
     * @notice Checks if a namespace represents an EVM-compatible chain
     * @dev Currently supports "eip155" namespace
     * @param namespace The namespace string to check
     * @return true if the namespace is EVM-compatible
     */
    function isEvmNamespace(string memory namespace) internal pure returns (bool) {
        return keccak256(bytes(namespace)) == keccak256(bytes("eip155"));
    }

    /**
     * @notice Checks if a namespace represents a Cosmos-compatible chain
     * @dev Supports "cosmos" namespace
     * @param namespace The namespace string to check
     * @return true if the namespace is Cosmos-compatible
     */
    function isCosmosNamespace(string memory namespace) internal pure returns (bool) {
        return keccak256(bytes(namespace)) == keccak256(bytes("cosmos"));
    }

    /**
     * @notice Checks if a namespace represents a Bitcoin-compatible chain
     * @dev Supports "bip122" namespace
     * @param namespace The namespace string to check
     * @return true if the namespace is Bitcoin-compatible
     */
    function isBitcoinNamespace(string memory namespace) internal pure returns (bool) {
        return keccak256(bytes(namespace)) == keccak256(bytes("bip122"));
    }

    /**
     * @notice Checks if a namespace represents a Solana chain
     * @dev Supports "solana" namespace
     * @param namespace The namespace string to check
     * @return true if the namespace is Solana
     */
    function isSolanaNamespace(string memory namespace) internal pure returns (bool) {
        return keccak256(bytes(namespace)) == keccak256(bytes("solana"));
    }

    /**
     * @notice Validates if a CAIP-10 identifier is for an EVM chain
     * @dev Combines validation and namespace checking
     * @param caip10 The complete CAIP-10 identifier to check
     * @return true if the identifier is valid and for an EVM chain
     */
    function isEvmCaip10(string memory caip10) internal pure returns (bool) {
        if (!validateCaip10(caip10)) return false;
        (string memory namespace,,) = parseCaip10(caip10);
        return isEvmNamespace(namespace);
    }

    // ═════════════════════════════════════════════════════════════════════════════════════════════
    // UTILITY FUNCTIONS
    // ═════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Extracts a substring from a string
     * @dev Used internally for parsing CAIP-10 components
     * @param str The source string
     * @param startIndex The starting index (inclusive)
     * @param endIndex The ending index (exclusive)
     * @return The extracted substring
     */
    function substring(string memory str, uint256 startIndex, uint256 endIndex) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(endIndex - startIndex);

        for (uint256 i = startIndex; i < endIndex; i++) {
            result[i - startIndex] = strBytes[i];
        }

        return string(result);
    }

    /**
     * @notice Compares two strings for equality
     * @dev Gas-efficient string comparison using keccak256
     * @param a First string
     * @param b Second string
     * @return true if strings are equal
     */
    function stringEquals(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    /**
     * @notice Legacy alias for parseEvmAddress for backward compatibility
     * @dev This function exists for backward compatibility with existing code
     * @param addressStr The address string to parse
     * @return The parsed Ethereum address
     */
    function parseAddress(string memory addressStr) public pure returns (address) {
        return parseEvmAddress(addressStr);
    }
}
