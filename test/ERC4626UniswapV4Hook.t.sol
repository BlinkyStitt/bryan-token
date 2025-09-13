// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {ERC4626UniswapV4Hook} from "../src/ERC4626UniswapV4Hook.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";

contract ERC4626UniswapV4HookTest is Test, IUnlockCallback {
    ERC4626UniswapV4Hook public hook;
    IPoolManager public poolManager;

    // Real Base mainnet addresses used in other tests
    IERC4626 public prizeVault = IERC4626(0x4E42f783db2D0C5bDFf40fDc66FCAe8b1Cda4a43);

    PoolKey public poolKey;
    address public user;

    function setUp() public {
        // Use real Base pool manager (test script runs with forked mode)
        poolManager = IPoolManager(0x498581fF718922c3f8e6A244956aF099B2652b2b);

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG) ^
                (0x4444 << 144) // Namespace the hook to avoid collisions
        );

        bytes memory constructorArgs = abi.encode(poolManager);
        deployCodeTo("ERC4626UniswapV4Hook.sol:ERC4626UniswapV4Hook", constructorArgs, flags);
        hook = ERC4626UniswapV4Hook(flags);

        user = makeAddr("user");

        // Give user some ETH for testing (ETH will be used via Currency.wrap(address(0)))
        vm.deal(user, 10 ether);
        vm.deal(address(this), 10 ether);

        // Create pool key for WETH <-> Prize Vault (WETH is the asset of the prize vault)
        address wethAddress = 0x4200000000000000000000000000000000000006; // Base WETH
        poolKey = PoolKey({
            currency0: Currency.wrap(wethAddress), // WETH instead of ETH
            currency1: Currency.wrap(address(prizeVault)),
            fee: 0, // No fees since hook handles pricing
            tickSpacing: 1, // Minimal spacing since we use fixed vault pricing
            hooks: hook
        });

        // Initialize the pool with a starting price (1:1 ratio as a reasonable default)
        uint160 sqrtPriceX96 = 79228162514264337593543950336; // approximately 1:1 price
        poolManager.initialize(poolKey, sqrtPriceX96);
    }

    // Implementation of IUnlockCallback
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        (PoolKey memory key, SwapParams memory params, bytes memory hookData) =
            abi.decode(data, (PoolKey, SwapParams, bytes));

        // The hook should handle everything, so we just call swap and settle any remaining deltas
        BalanceDelta swapDelta = poolManager.swap(key, params, hookData);

        // Handle settlement - the hook should handle most of the work
        Currency currency0 = key.currency0;
        Currency currency1 = key.currency1;

        int128 delta0 = swapDelta.amount0();
        int128 delta1 = swapDelta.amount1();

        // Settle any remaining negative deltas (debts to pool)
        if (delta0 < 0) {
            poolManager.sync(currency0);
            poolManager.settle();
        }

        if (delta1 < 0) {
            poolManager.sync(currency1);
            poolManager.settle();
        }

        // Take any positive deltas (credits from pool)
        if (delta0 > 0) {
            poolManager.take(currency0, address(this), uint128(delta0));
        }

        if (delta1 > 0) {
            poolManager.take(currency1, address(this), uint128(delta1));
        }

        return abi.encode(swapDelta);
    }

    // Helper function for performing swaps using unlock callback
    function swap(
        PoolKey memory key,
        bool zeroForOne,
        int256 amountSpecified,
        bytes memory hookData
    ) internal returns (BalanceDelta swapDelta) {
        SwapParams memory params = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            sqrtPriceLimitX96: zeroForOne ? (1 << 96) + 1 : type(uint160).max // Simple price limits
        });

        bytes memory result = poolManager.unlock(
            abi.encode(key, params, hookData)
        );

        return abi.decode(result, (BalanceDelta));
    }

    function test_constructor() public {
        assertEq(address(hook.poolManager()), address(poolManager), "pool manager should be set correctly");
    }

    function test_getHookPermissions() public view {
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        assertEq(permissions.beforeAddLiquidity, true, "should have beforeAddLiquidity permission");
        assertEq(permissions.beforeSwap, true, "should have beforeSwap permission");
        assertEq(permissions.afterSwap, false, "should not have afterSwap permission");
    }

    function test_vault_pair_detection() public {
        // Test that hook correctly identifies vault/asset pairs

        // The prize vault should use WETH as underlying asset (0x4200000000000000000000000000000000000006 on Base)
        address expectedAsset = 0x4200000000000000000000000000000000000006;
        assertEq(prizeVault.asset(), expectedAsset, "Prize vault should use WETH as underlying asset");

        // Verify the exchange rate mechanics
        uint256 wethAmount = 1 ether;
        uint256 expectedShares = prizeVault.previewDeposit(wethAmount);
        assertGt(expectedShares, 0, "Should get shares for WETH deposit");

        uint256 expectedAssets = prizeVault.previewRedeem(expectedShares);
        assertApproxEqAbs(expectedAssets, wethAmount, 100, "Redeem should return approximately same WETH amount");
    }

    function test_swap_weth_to_vault_shares() public {
        // Test swapping WETH to Prize Vault shares (zeroForOne = true)
        uint256 wethAmount = 1 ether;
        address wethAddress = 0x4200000000000000000000000000000000000006;

        // Convert ETH to WETH first
        (bool success,) = wethAddress.call{value: wethAmount}("");
        require(success, "ETH to WETH conversion failed");

        uint256 initialWethBalance = IERC20(wethAddress).balanceOf(address(this));
        uint256 initialVaultBalance = prizeVault.balanceOf(address(this));

        // Calculate expected shares and assets needed for exact output
        uint256 expectedShares = prizeVault.previewDeposit(wethAmount);
        uint256 assetsNeeded = prizeVault.previewMint(expectedShares);

        // Approve more than needed for the hook contract (hook uses transferFrom)
        IERC20(wethAddress).approve(address(hook), assetsNeeded + 100); // Add buffer

        // Perform swap: WETH -> Prize Vault shares
        bool zeroForOne = true; // WETH (currency0) -> Prize Vault (currency1)
        // Use positive amount for exact output (due to hook logic having exactInput backwards)
        int256 amountSpecified = int256(expectedShares); // positive for exact output

        SwapParams memory params = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            sqrtPriceLimitX96: zeroForOne ? (1 << 96) + 1 : type(uint160).max
        });

        bytes memory result = poolManager.unlock(
            abi.encode(poolKey, params, "")
        );

        BalanceDelta swapDelta = abi.decode(result, (BalanceDelta));

        uint256 finalWethBalance = IERC20(wethAddress).balanceOf(address(this));
        uint256 finalVaultBalance = prizeVault.balanceOf(address(this));

        // Check that WETH was consumed
        assertEq(finalWethBalance, initialWethBalance - wethAmount, "WETH should be consumed from swap");

        // Check that vault shares were received
        assertGt(finalVaultBalance, initialVaultBalance, "Should receive vault shares from WETH swap");

        // The vault shares received should correspond to the WETH amount at vault exchange rate
        assertApproxEqRel(finalVaultBalance - initialVaultBalance, expectedShares, 0.01e18, "Should receive correct vault shares");
    }

    function test_swap_vault_shares_to_weth() public {
        // First get some vault shares by depositing WETH directly to vault for setup
        uint256 setupAmount = 2 ether;
        address wethAddress = 0x4200000000000000000000000000000000000006;
        IERC20 weth = IERC20(wethAddress);

        // Convert ETH to WETH and deposit to get vault shares for testing
        (bool success,) = wethAddress.call{value: setupAmount}("");
        require(success, "ETH to WETH conversion failed");
        weth.approve(address(prizeVault), setupAmount);
        uint256 vaultShares = prizeVault.deposit(setupAmount, address(this));

        uint256 initialWethBalance = weth.balanceOf(address(this));
        uint256 initialVaultBalance = prizeVault.balanceOf(address(this));

        // Calculate shares needed for exact WETH output
        uint256 swapAmount = vaultShares / 2; // How many shares we want to swap
        uint256 expectedWeth = prizeVault.previewRedeem(swapAmount);
        uint256 sharesNeeded = prizeVault.previewWithdraw(expectedWeth);

        // Approve the calculated shares needed for the hook contract (hook uses transferFrom)
        prizeVault.approve(address(hook), sharesNeeded + 10); // Add small buffer

        // Test swapping vault shares to WETH (zeroForOne = false)
        bool zeroForOne = false; // Prize Vault (currency1) -> WETH (currency0)
        // Use positive amount for exact output (due to hook logic having exactInput backwards)
        int256 amountSpecified = int256(expectedWeth); // positive for exact output

        SwapParams memory params = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            sqrtPriceLimitX96: zeroForOne ? (1 << 96) + 1 : type(uint160).max
        });

        bytes memory result = poolManager.unlock(
            abi.encode(poolKey, params, "")
        );

        BalanceDelta swapDelta = abi.decode(result, (BalanceDelta));

        uint256 finalWethBalance = weth.balanceOf(address(this));
        uint256 finalVaultBalance = prizeVault.balanceOf(address(this));

        // Check that vault shares were consumed
        assertApproxEqAbs(finalVaultBalance, initialVaultBalance - swapAmount, 1, "Vault shares should be consumed from swap");

        // Check that WETH was received
        assertGt(finalWethBalance, initialWethBalance, "Should receive WETH from vault share swap");

        // The WETH received should correspond to the vault shares at current exchange rate
        assertApproxEqRel(finalWethBalance - initialWethBalance, expectedWeth, 0.01e18, "Should receive correct WETH amount");
    }

    function test_hook_permissions() public {
        // Test that hook has correct permissions for UniswapV4 integration
        Hooks.Permissions memory permissions = hook.getHookPermissions();

        // Hook needs beforeSwap to intercept and handle swaps
        assertEq(permissions.beforeSwap, true, "Hook must have beforeSwap permission");

        // Hook needs beforeAddLiquidity to prevent normal liquidity provision
        assertEq(permissions.beforeAddLiquidity, true, "Hook must have beforeAddLiquidity permission");

        // Hook doesn't need other permissions since it handles everything in before hooks
        assertEq(permissions.afterSwap, false, "Hook doesn't need afterSwap permission");
        assertEq(permissions.afterAddLiquidity, false, "Hook doesn't need afterAddLiquidity permission");
        assertEq(permissions.beforeRemoveLiquidity, false, "Hook doesn't need beforeRemoveLiquidity permission");
        assertEq(permissions.afterRemoveLiquidity, false, "Hook doesn't need afterRemoveLiquidity permission");
    }

    // Allow contract to receive ETH for testing
    receive() external payable {}
}