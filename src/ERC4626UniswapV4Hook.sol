// SPDX-License-Identifier: AGPL-3.0-only
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
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {Unimplemented} from "./FanToken.sol";

/**
 * @dev A hook that replaces swaps with ERC4626 vault deposits/redeems
 * Supports pools between an ERC4626 vault and its underlying asset
 * Can be chained: WETH -> WETH Prize Vault -> Fan Token
 */
contract ERC4626UniswapV4Hook is BaseHook {
    using SafeERC20 for IERC20;
    using CurrencyLibrary for Currency;
    using BalanceDeltaLibrary for BalanceDelta;

    error InvalidTokenPair();
    error UnsupportedSwap();

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory p) {
        p.beforeAddLiquidity = true;
        p.beforeSwap = true;
    }

    function _beforeAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        internal
        override
        returns (bytes4)
    {
        // No liquidity providers - this hook handles all swaps via vault deposits/redeems
        revert UnsupportedSwap();
    }

    function _beforeSwap(address, PoolKey calldata key, SwapParams calldata params, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // Determine which tokens are involved
        Currency currency0 = key.currency0;
        Currency currency1 = key.currency1;

        address token0 = Currency.unwrap(currency0);
        address token1 = Currency.unwrap(currency1);

        // Check if one is an ERC4626 vault and the other is its asset
        (bool isVault0, bool isVault1) = _checkVaultPair(token0, token1);

        if (!isVault0 && !isVault1) {
            revert InvalidTokenPair();
        }

        // Determine swap direction and amounts
        bool zeroForOne = params.zeroForOne;
        int256 amountSpecified = params.amountSpecified;
        bool exactInput = amountSpecified > 0;

        BalanceDelta delta;

        if (isVault0 && !isVault1) {
            // token0 is vault, token1 is asset
            if (zeroForOne) {
                // Swapping vault shares -> asset (redeem)
                delta = _handleRedeem(token0, token1, amountSpecified, exactInput);
            } else {
                // Swapping asset -> vault shares (deposit)
                delta = _handleDeposit(token0, token1, amountSpecified, exactInput);
            }
        } else if (!isVault0 && isVault1) {
            // token0 is asset, token1 is vault
            if (zeroForOne) {
                // Swapping asset -> vault shares (deposit)
                delta = _handleDeposit(token1, token0, amountSpecified, exactInput);
            } else {
                // Swapping vault shares -> asset (redeem)
                delta = _handleRedeem(token1, token0, amountSpecified, exactInput);
            }
        } else {
            revert UnsupportedSwap();
        }

        BeforeSwapDelta hookDelta = BeforeSwapDelta.wrap(BalanceDelta.unwrap(delta));

        // Return hook signature and delta
        return (bytes4(keccak256("_beforeSwap(address,(address,address,uint24,int24,address),int256,bool,bytes)")), hookDelta, 0);
    }

    /**
     * @dev Check if the token pair consists of an ERC4626 vault and its asset
     */
    function _checkVaultPair(address token0, address token1) internal view returns (bool isVault0, bool isVault1) {
        // Check if token0 is a vault with token1 as its asset
        try IERC4626(token0).asset() returns (address asset0) {
            if (asset0 == token1) {
                isVault0 = true;
            }
        } catch {}

        // Check if token1 is a vault with token0 as its asset
        try IERC4626(token1).asset() returns (address asset1) {
            if (asset1 == token0) {
                isVault1 = true;
            }
        } catch {}
    }

    /**
     * @dev Handle deposit: asset -> vault shares
     */
    function _handleDeposit(address vault, address asset, int256 amountSpecified, bool exactInput)
        internal
        returns (BalanceDelta)
    {
        uint256 amount = uint256(amountSpecified < 0 ? -amountSpecified : amountSpecified);

        if (exactInput) {
            // Exact asset amount in, get vault shares out
            IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
            IERC20(asset).forceApprove(vault, amount);

            uint256 sharesReceived = IERC4626(vault).deposit(amount, msg.sender);

            // Return negative delta for asset (taken from user) and positive for vault shares (given to user)
            return BalanceDelta.wrap(int256(sharesReceived));
        } else {
            // Exact vault shares out, calculate asset amount needed
            uint256 assetsNeeded = IERC4626(vault).previewMint(amount);

            IERC20(asset).safeTransferFrom(msg.sender, address(this), assetsNeeded);
            IERC20(asset).forceApprove(vault, assetsNeeded);

            IERC4626(vault).mint(amount, msg.sender);

            return BalanceDelta.wrap(int256(amount));
        }
    }

    /**
     * @dev Handle redeem: vault shares -> asset
     */
    function _handleRedeem(address vault, address asset, int256 amountSpecified, bool exactInput)
        internal
        returns (BalanceDelta)
    {
        uint256 amount = uint256(amountSpecified < 0 ? -amountSpecified : amountSpecified);

        if (exactInput) {
            // Exact vault shares in, get asset out
            IERC20(vault).safeTransferFrom(msg.sender, address(this), amount);
            uint256 assetsReceived = IERC4626(vault).redeem(amount, msg.sender, address(this));

            return BalanceDelta.wrap(-int256(assetsReceived));
        } else {
            // Exact asset out, calculate vault shares needed
            uint256 sharesNeeded = IERC4626(vault).previewWithdraw(amount);

            IERC20(vault).safeTransferFrom(msg.sender, address(this), sharesNeeded);
            IERC4626(vault).withdraw(amount, msg.sender, address(this));

            return BalanceDelta.wrap(-int256(amount));
        }
    }
}
