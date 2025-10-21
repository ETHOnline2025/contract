// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Test.sol";
import {Caip10Utils} from "@EVVM/testnet/lib/Caip10Utils.sol";

contract Caip10UtilsTest is Test {
    function testParseCaip10Valid() public {
        string memory caip10 = "eip155:1:0xab16a96D359eC26a11e2C2b3d8f8B8942d5Bfcdb";
        (string memory namespace, string memory chainId, string memory accountAddress) =
            Caip10Utils.parseCaip10(caip10);

        assertEq(namespace, "eip155");
        assertEq(chainId, "1");
        assertEq(accountAddress, "0xab16a96D359eC26a11e2C2b3d8f8B8942d5Bfcdb");
    }

    function testParseCaip10Arbitrum() public {
        string memory caip10 = "eip155:42161:0x1234567890123456789012345678901234567890";
        (string memory namespace, string memory chainId, string memory accountAddress) =
            Caip10Utils.parseCaip10(caip10);

        assertEq(namespace, "eip155");
        assertEq(chainId, "42161");
        assertEq(accountAddress, "0x1234567890123456789012345678901234567890");
    }

    function testValidateCaip10InvalidFormatNoColon() public pure {
        string memory caip10 = "eip1551";
        bool isValid = Caip10Utils.validateCaip10(caip10);
        assert(!isValid);
    }

    function testValidateCaip10InvalidFormatOneColon() public pure {
        string memory caip10 = "eip155:1";
        bool isValid = Caip10Utils.validateCaip10(caip10);
        assert(!isValid);
    }

    function testValidateCaip10Empty() public pure {
        string memory caip10 = "";
        bool isValid = Caip10Utils.validateCaip10(caip10);
        assert(!isValid);
    }

    function testExtractAddress() public {
        string memory caip10 = "eip155:1:0xab16a96D359eC26a11e2C2b3d8f8B8942d5Bfcdb";
        address extracted = Caip10Utils.extractAddress(caip10);

        assertEq(extracted, 0xab16a96D359eC26a11e2C2b3d8f8B8942d5Bfcdb);
    }

    function testExtractAddressLowercase() public {
        string memory caip10 = "eip155:1:0xabcdef1234567890abcdef1234567890abcdef12";
        address extracted = Caip10Utils.extractAddress(caip10);

        assertEq(extracted, address(0xabCDEF1234567890ABcDEF1234567890aBCDeF12));
    }

    function testParseAddressValid() public {
        string memory addrStr = "0xab16a96D359eC26a11e2C2b3d8f8B8942d5Bfcdb";
        address parsed = Caip10Utils.parseAddress(addrStr);

        assertEq(parsed, 0xab16a96D359eC26a11e2C2b3d8f8B8942d5Bfcdb);
    }


    function testToCaip10() public {
        address account = 0xab16a96D359eC26a11e2C2b3d8f8B8942d5Bfcdb;
        string memory caip10 = Caip10Utils.toCaip10("eip155", "1", account);

        assertEq(caip10, "eip155:1:0xab16a96d359ec26a11e2c2b3d8f8b8942d5bfcdb");
    }

    function testToCaip10Arbitrum() public {
        address account = 0x1234567890123456789012345678901234567890;
        string memory caip10 = Caip10Utils.toCaip10("eip155", "42161", account);

        assertEq(caip10, "eip155:42161:0x1234567890123456789012345678901234567890");
    }

    function testToHexString() public {
        address account = 0xab16a96D359eC26a11e2C2b3d8f8B8942d5Bfcdb;
        string memory hexStr = Caip10Utils.toHexString(account);

        assertEq(hexStr, "0xab16a96d359ec26a11e2c2b3d8f8b8942d5bfcdb");
    }

    function testToHexStringZeroAddress() public {
        address account = address(0);
        string memory hexStr = Caip10Utils.toHexString(account);

        assertEq(hexStr, "0x0000000000000000000000000000000000000000");
    }

    function testSubstring() public {
        string memory str = "Hello, World!";
        string memory sub = Caip10Utils.substring(str, 0, 5);

        assertEq(sub, "Hello");
    }

    function testSubstringMiddle() public {
        string memory str = "Hello, World!";
        string memory sub = Caip10Utils.substring(str, 7, 12);

        assertEq(sub, "World");
    }

    function testSubstringFull() public {
        string memory str = "Test";
        string memory sub = Caip10Utils.substring(str, 0, 4);

        assertEq(sub, "Test");
    }

    function testValidateCaip10Valid() public {
        string memory caip10 = "eip155:1:0xab16a96D359eC26a11e2C2b3d8f8B8942d5Bfcdb";
        bool isValid = Caip10Utils.validateCaip10(caip10);

        assertTrue(isValid);
    }

    function testValidateCaip10Invalid() public {
        string memory caip10 = "invalid";
        bool isValid = Caip10Utils.validateCaip10(caip10);

        assertFalse(isValid);
    }

    function testRoundTripConversion() public {
        address original = 0xab16a96D359eC26a11e2C2b3d8f8B8942d5Bfcdb;
        string memory caip10 = Caip10Utils.toCaip10("eip155", "1", original);
        address extracted = Caip10Utils.extractAddress(caip10);

        assertEq(original, extracted);
    }

    function testFuzzParseAddress(address randomAddr) public {
        string memory hexStr = Caip10Utils.toHexString(randomAddr);
        address parsed = Caip10Utils.parseAddress(hexStr);

        assertEq(parsed, randomAddr);
    }

    function testFuzzToCaip10(address randomAddr) public {
        string memory caip10 = Caip10Utils.toCaip10("eip155", "1", randomAddr);
        address extracted = Caip10Utils.extractAddress(caip10);

        assertEq(extracted, randomAddr);
    }
}
