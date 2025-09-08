// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {
    BaseHook,
    BeforeSwapDelta,
    Hooks,
    IPoolManager,
    ModifyLiquidityParams,
    PoolKey,
    SwapParams
} from "v4-periphery/src/utils/BaseHook.sol";

/**
 * @dev A hook that replaces swaps with ERC4626 vault deposits/redeems
 * TODO: write the contract
 * TODO: i think we will deploy two uniswap v4 pools to use this. one will be asset() <-> underlying(). and the other will be fantoken <-> asset()
 * TODO: how will uniswap interfaces know that this hook has liquidity? We need to have it query the underlying contact and maxRedeem I think
 */
contract ERC4626UniswapV4Hook is BaseHook {
    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory p) {
        p.beforeAddLiquidity = true;
        p.beforeSwap = true;
    }

    function _beforeAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        internal
        virtual
        returns (bytes4)
    {
        // todo: i think this should revert. there's no need to have actual liquidity in this contract.
        revert("todo: write this");
    }

    function _beforeSwap(address, PoolKey calldata, SwapParams calldata, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // TODO: figure out what tokens are involved. it should be two ERC4626 tokens. one of the tokens must use the other as its underlying asset

        // TODO: either deposit or redeem

        // TODO: there are some events to emit so that off-chain processing can correctly process this swap

        revert("todo: write this");
    }

    // TODO: write _beforeDonate?
}
