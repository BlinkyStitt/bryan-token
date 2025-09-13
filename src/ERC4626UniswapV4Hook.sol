// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {DeltaResolver} from "v4-periphery/src/base/DeltaResolver.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {toBeforeSwapDelta, BeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Unimplemented} from "./FanToken.sol";

/**
 * @dev A hook that replaces swaps with ERC4626 vault deposits/redeems
 * Supports pools between an ERC4626 vault and its underlying asset
 * Can be chained: WETH -> WETH Prize Vault -> Fan Token
 */
contract ERC4626UniswapV4Hook is BaseHook, DeltaResolver {
    using SafeERC20 for IERC20;
    using CurrencyLibrary for Currency;
    using SafeCast for uint256;
    using SafeCast for int256;

    error InvalidTokenPair();
    error UnsupportedSwap();

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    /**
     * @dev Helper function to create hookData with user address
     */
    function getHookData(address user) external pure returns (bytes memory) {
        return abi.encode(user);
    }

    /**
     * @dev Helper function to parse user address from hookData
     */
    function _parseHookData(bytes calldata hookData) internal pure returns (address) {
        if (hookData.length == 0) {
            revert("Hook data is required");
        }
        return abi.decode(hookData, (address));
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory p) {
        p.beforeAddLiquidity = true;
        p.beforeSwap = true;
        p.beforeSwapReturnDelta = true;
    }

    function _beforeAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        internal
        override
        returns (bytes4)
    {
        // No liquidity providers - this hook handles all swaps via vault deposits/redeems
        revert UnsupportedSwap();
    }

    function _beforeSwap(address, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // Extract user address from hookData
        address user = _parseHookData(hookData);

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

        bool isExactInput = params.amountSpecified < 0;
        uint256 amount = uint256(isExactInput ? -params.amountSpecified : params.amountSpecified);

        int128 amountUnspecified;

        if (isVault0 && !isVault1) {
            // token0 is vault, token1 is asset
            if (params.zeroForOne) {
                // Swapping vault shares -> asset (redeem)
                amountUnspecified = _handleRedeem(token0, token1, amount, isExactInput, user);
            } else {
                // Swapping asset -> vault shares (deposit)
                amountUnspecified = _handleDeposit(token0, token1, amount, isExactInput, user);
            }
        } else if (!isVault0 && isVault1) {
            // token0 is asset, token1 is vault
            if (params.zeroForOne) {
                // Swapping asset -> vault shares (deposit)
                amountUnspecified = _handleDeposit(token1, token0, amount, isExactInput, user);
            } else {
                // Swapping vault shares -> asset (redeem)
                amountUnspecified = _handleRedeem(token1, token0, amount, isExactInput, user);
            }
        } else {
            revert UnsupportedSwap();
        }

        // Simple approach: return zero delta and let normal swap handling occur
        BeforeSwapDelta hookDelta = toBeforeSwapDelta(0, 0);
        return (IHooks.beforeSwap.selector, hookDelta, 0);
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
     * @return amountUnspecified The unspecified amount for the BeforeSwapDelta
     */
    function _handleDeposit(address vault, address asset, uint256 amount, bool exactInput, address user)
        internal
        returns (int128 amountUnspecified)
    {
        Currency assetCurrency = Currency.wrap(asset);
        Currency vaultCurrency = Currency.wrap(vault);

        if (exactInput) {
            // Exact asset amount in, get vault shares out
            // Take user's assets, deposit to get vault shares
            IERC20(asset).safeTransferFrom(user, address(this), amount);
            IERC20(asset).forceApprove(vault, amount);
            uint256 sharesReceived = IERC4626(vault).deposit(amount, address(this));

            // Transfer the vault shares to the user
            IERC20(vault).safeTransfer(user, sharesReceived);

            // Return negative shares (user receives them)
            return -(sharesReceived.toInt256().toInt128());
        } else {
            // Exact vault shares out, calculate asset amount needed
            uint256 assetsNeeded = IERC4626(vault).previewMint(amount);

            // Take asset from PoolManager and mint exact vault shares to hook
            _take(assetCurrency, address(this), assetsNeeded);
            IERC20(asset).forceApprove(vault, assetsNeeded);
            IERC4626(vault).mint(amount, address(this));

            // Settle vault shares to PoolManager
            _settle(vaultCurrency, address(this), amount);

            // Return positive assets (pool manager gets them back)
            return assetsNeeded.toInt256().toInt128();
        }
    }

    /**
     * @dev Handle redeem: vault shares -> asset
     * @return amountUnspecified The unspecified amount for the BeforeSwapDelta
     */
    function _handleRedeem(address vault, address asset, uint256 amount, bool exactInput, address user)
        internal
        returns (int128 amountUnspecified)
    {
        Currency assetCurrency = Currency.wrap(asset);
        Currency vaultCurrency = Currency.wrap(vault);

        if (exactInput) {
            // Exact vault shares in, get asset out
            // Take vault shares from PoolManager and redeem
            _take(vaultCurrency, address(this), amount);
            uint256 assetsReceived = IERC4626(vault).redeem(amount, user, address(this));

            // Settle assets to PoolManager
            _settle(assetCurrency, address(this), assetsReceived);

            // Return negative assets (user receives them)
            return -(assetsReceived.toInt256().toInt128());
        } else {
            // Exact asset out, calculate vault shares needed
            uint256 sharesNeeded = IERC4626(vault).previewWithdraw(amount);

            // Take vault shares from PoolManager and withdraw exact assets to user
            _take(vaultCurrency, address(this), sharesNeeded);
            IERC4626(vault).withdraw(amount, user, address(this));

            // Settle assets to PoolManager
            _settle(assetCurrency, address(this), amount);

            // Return positive shares (pool manager gets them back)
            return sharesNeeded.toInt256().toInt128();
        }
    }

    /// @notice Transfer tokens to the pool manager
    /// @param currency The currency to transfer
    /// @param amount The amount to transfer
    function _pay(Currency currency, address, uint256 amount) internal override {
        currency.transfer(address(poolManager), amount);
    }
}
