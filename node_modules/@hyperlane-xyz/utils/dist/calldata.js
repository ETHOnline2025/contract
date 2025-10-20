export function formatCallData(destinationContract, functionName, functionArgs) {
    return destinationContract.interface.encodeFunctionData(functionName, functionArgs);
}
//# sourceMappingURL=calldata.js.map