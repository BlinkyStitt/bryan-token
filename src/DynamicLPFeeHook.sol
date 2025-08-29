// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseDynamicFee, IPoolManager, PoolKey} from "@openzeppelin-uniswap-hooks/fee/BaseDynamicFee.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @dev A hook that allows the owner to dynamically update the LP fee.
 */
contract DynamicLPFeeHook is BaseDynamicFee, Ownable {
    uint24 public fee;

    constructor(IPoolManager _poolManager) BaseDynamicFee(_poolManager) Ownable(msg.sender) {}

    /**
     * @inheritdoc BaseDynamicFee
     */
    function _getFee(PoolKey calldata) internal view override returns (uint24) {
        return fee;
    }

    /**
     * @notice Sets the LP fee, denominated in hundredths of a bip.
     */
    function setFee(uint24 _fee) external onlyOwner {
        fee = _fee;
    }
}