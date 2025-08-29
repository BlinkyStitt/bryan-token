// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook, Hooks, IPoolManager} from "v4-periphery/src/utils/BaseHook.sol";

/**
 * @dev A hook that replaces swaps with ERC4626 vault deposits/redeems
 * TODO: write the contract
 */
contract FanTokenUniswapV4Hook is BaseHook {
    constructor(address _fanToken, IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory p) {
        p.beforeSwap = true;
        p.beforeAddLiquidity = true;
    }
}
