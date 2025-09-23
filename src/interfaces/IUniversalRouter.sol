// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface IUniversalRouter {
    /// @notice Executes encoded commands along with provided inputs
    /// @param commands A set of concatenated commands, each 1 byte in length
    /// @param inputs An array of byte strings containing abi encoded inputs for each command
    /// @param deadline The deadline by which the transaction must be executed
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable;
}

library Commands {
    uint256 constant V4_SWAP = 0x00;
}

library Actions {
    uint256 constant SWAP_EXACT_IN_SINGLE = 0x00;
    uint256 constant SETTLE_ALL = 0x12;
    uint256 constant TAKE_ALL = 0x13;
}
