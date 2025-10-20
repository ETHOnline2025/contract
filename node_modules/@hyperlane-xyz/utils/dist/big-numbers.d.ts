import { BigNumber } from 'bignumber.js';
import { FixedNumber } from 'ethers';
/**
 * Check if a value is bigNumberish (e.g. valid numbers, bigNumber).
 * @param value The value to check.
 * @returns true/false.
 */
export declare function isBigNumberish(value: BigNumber.Value | undefined | null): boolean;
/**
 * Check if a value (e.g. hex string or number) is zeroish (0, 0x0, 0x00, etc.).
 * @param value The value to check.
 * @returns true/false.
 */
export declare function isZeroish(value: BigNumber.Value): boolean;
/**
 * Converts a BigNumber to a FixedNumber of the format fixed128x18.
 * @param big The BigNumber to convert.
 * @returns A FixedNumber representation of a BigNumber.
 */
export declare function bigToFixed(big: BigNumber.Value): FixedNumber;
/**
 * Converts a FixedNumber (of any format) to a BigNumber.
 * @param fixed The FixedNumber to convert.
 * @param ceil If true, the ceiling of fixed is used. Otherwise, the floor is used.
 * @returns A BigNumber representation of a FixedNumber.
 */
export declare function fixedToBig(fixed: FixedNumber, ceil?: boolean): BigNumber;
/**
 * Multiplies a BigNumber by a FixedNumber, returning the BigNumber product.
 * @param big The BigNumber to multiply.
 * @param fixed The FixedNumber to multiply.
 * @param ceil If true, the ceiling of the product is used. Otherwise, the floor is used.
 * @returns The BigNumber product in string type.
 */
export declare function mulBigAndFixed(big: BigNumber.Value, fixed: FixedNumber, ceil?: boolean): string;
/**
 * Return the smaller in the given two BigNumbers.
 * @param bn1 The BigNumber to compare.
 * @param bn2 The BigNumber to compare.
 * @returns The smaller BigNumber in string type.
 */
export declare function BigNumberMin(bn1: BigNumber.Value, bn2: BigNumber.Value): string;
/**
 * Return the bigger in the given two BigNumbers.
 * @param bn1 The BigNumber to compare.
 * @param bn2 The BigNumber to compare.
 * @returns The bigger BigNumber in string type.
 */
export declare function BigNumberMax(bn1: BigNumber.Value, bn2: BigNumber.Value): string;
//# sourceMappingURL=big-numbers.d.ts.map