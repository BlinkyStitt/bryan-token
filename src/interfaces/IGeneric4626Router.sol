// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";

interface IGeneric4626Router {
    type BeforeSwapDelta is int256;

    struct ModifyLiquidityParams {
        int24 tickLower;
        int24 tickUpper;
        int256 liquidityDelta;
        bytes32 salt;
    }

    struct SwapParams {
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
    }

    error Generic4626Router__InvalidPoolFee();
    error Generic4626Router__NotAllowed();
    error HookNotImplemented();
    error InvalidPool();
    error NotPoolManager();
    error NotSelf();

    function afterAddLiquidity(
        address sender,
        PoolKey memory key,
        ModifyLiquidityParams memory params,
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
        ModifyLiquidityParams memory params,
        BalanceDelta delta0,
        BalanceDelta delta1,
        bytes memory hookData
    ) external returns (bytes4, BalanceDelta);
    function afterSwap(
        address sender,
        PoolKey memory key,
        SwapParams memory params,
        BalanceDelta delta,
        bytes memory hookData
    ) external returns (bytes4, int128);
    function beforeAddLiquidity(
        address sender,
        PoolKey memory key,
        ModifyLiquidityParams memory params,
        bytes memory hookData
    ) external returns (bytes4);
    function beforeDonate(address sender, PoolKey memory key, uint256 amount0, uint256 amount1, bytes memory hookData)
        external
        returns (bytes4);
    function beforeInitialize(address sender, PoolKey memory key, uint160 sqrtPriceX96) external returns (bytes4);
    function beforeRemoveLiquidity(
        address sender,
        PoolKey memory key,
        ModifyLiquidityParams memory params,
        bytes memory hookData
    ) external returns (bytes4);
    function beforeSwap(address sender, PoolKey memory key, SwapParams memory params, bytes memory hookData)
        external
        returns (bytes4, BeforeSwapDelta, uint24);
    function getHookPermissions() external pure returns (Hooks.Permissions memory);
    function initializePool(address vault) external returns (PoolKey memory poolKey, PoolId poolId);
    function poolDetails(PoolId poolId) external view returns (bool isInitialized, bool wrapsZeroToOne);
    function poolManager() external view returns (address);
}
