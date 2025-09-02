// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook, Hooks, IPoolManager} from "v4-periphery/src/utils/BaseHook.sol";

/**
 * @dev A hook that replaces swaps with ERC4626 vault deposits/redeems
 * TODO: write the contract
 * TODO: i think we will deploy two uniswap v4 pools to use this. one will be asset() <-> underlying(). and the other will be fantoken <-> asset()
 * TODO: how will uniswap interfaces know that this hook has liquidity? We need to have it query the underlying contact and maxRedeem I think
 */
contract ERC4626UniswapV4Hook is BaseHook {
    constructor(address _fanToken, IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory p) {
        p.beforeSwap = true;
        p.beforeAddLiquidity = true;
    }

    // TODO: write _beforeSwap
    // TODO: write _beforeAddLiquidity. i think it should revert. there's no need to have actual liquidity in this contract
}
