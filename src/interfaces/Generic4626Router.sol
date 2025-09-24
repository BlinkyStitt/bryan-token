// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {BalanceDelta, PoolKey, PoolId, IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

interface Generic4626Router {

    error Generic4626Router__InvalidPoolFee();
    error Generic4626Router__NotAllowed();
    error HookNotImplemented();
    error InvalidPool();
    error NotPoolManager();
    error NotSelf();

    function afterAddLiquidity(
        address sender,
        PoolKey memory key,
        IPoolManager.ModifyLiquidityParams memory params,
        BalanceDelta delta0,
        BalanceDelta delta1,
        bytes memory hookData
    ) external returns (bytes4, BalanceDelta);
    function afterDonate(address sender, PoolKey memory key, uint256 amount0, uint256 amount1, bytes memory hookData)
        external
        returns (bytes4);
    function afterInitialize(address sender, PoolKey memory key, uint160 sqrtPriceX96, int24 tick)
        external
        returns (bytes4);
    function afterRemoveLiquidity(
        address sender,
        PoolKey memory key,
        IPoolManager.ModifyLiquidityParams memory params,
        BalanceDelta delta0,
        BalanceDelta delta1,
        bytes memory hookData
    ) external returns (bytes4, BalanceDelta);
    function afterSwap(
        address sender,
        PoolKey memory key,
        IPoolManager.SwapParams memory params,
        BalanceDelta delta,
        bytes memory hookData
    ) external returns (bytes4, int128);
    function beforeAddLiquidity(
        address sender,
        PoolKey memory key,
        IPoolManager.ModifyLiquidityParams memory params,
        bytes memory hookData
    ) external returns (bytes4);
    function beforeDonate(address sender, PoolKey memory key, uint256 amount0, uint256 amount1, bytes memory hookData)
        external
        returns (bytes4);
    function beforeInitialize(address sender, PoolKey memory key, uint160 sqrtPriceX96) external returns (bytes4);
    function beforeRemoveLiquidity(
        address sender,
        PoolKey memory key,
        IPoolManager.ModifyLiquidityParams memory params,
        bytes memory hookData
    ) external returns (bytes4);
    function beforeSwap(address sender, PoolKey memory key, IPoolManager.SwapParams memory params, bytes memory hookData)
        external
        returns (bytes4, BeforeSwapDelta, uint24);
    function getHookPermissions() external pure returns (Hooks.Permissions memory);
    function initializePool(address vault) external returns (PoolKey memory poolKey, PoolId poolId);
    function poolDetails(PoolId poolId) external view returns (bool isInitialized, bool wrapsZeroToOne);
    function poolManager() external view returns (address);
}
