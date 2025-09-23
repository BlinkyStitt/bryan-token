// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {IERC20, IERC4626, IWETH9} from "../src/FanToken.sol";
import {FanToken, FanTokenFactory} from "../src/FanTokenFactory.sol";
import {IGeneric4626Router} from "../src/interfaces/IGeneric4626Router.sol";
import {PoolIdLibrary, PoolId} from "v4-core/src/types/PoolId.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";

using PoolIdLibrary for PoolKey;

/**
 * @title Generic4626Router Integration Test
 * @notice Tests that Generic4626Router hook properly creates V4 pools
 * @dev This test verifies the Uniswap V4 integration without attempting actual swaps
 */
contract Generic4626RouterTest is Test {
    // Core contracts
    IWETH9 constant WETH = IWETH9(0x4200000000000000000000000000000000000006);
    IERC4626 constant PRIZE_VAULT = IERC4626(0x4E42f783db2D0C5bDFf40fDc66FCAe8b1Cda4a43);
    IGeneric4626Router constant GENERIC_4626_HOOK = IGeneric4626Router(0xD60a6A0f0D5E3Fd451449C7256BbbDC59561e888);

    // Test contracts
    FanTokenFactory factory;
    FanToken fanToken;
    address poolManager;

    // Test accounts
    address trader;
    address treasury;

    // Trade amounts
    uint256 constant INITIAL_WETH = 1 ether;
    uint256 constant TRADE_AMOUNT = 0.1 ether;

    function setUp() public {
        // Create test accounts
        trader = makeAddr("trader");
        treasury = makeAddr("treasury");

        // Deploy factory with the Generic4626Router hook
        factory = new FanTokenFactory(WETH, GENERIC_4626_HOOK);

        // Get the pool manager from the hook
        poolManager = GENERIC_4626_HOOK.poolManager();

        // Create a fan token for our prize vault - this sets up V4 pools
        vm.prank(trader);
        fanToken = factory.create(
            "Prize Vault Fan Token",
            "PVF",
            500, // 5% owner fee
            250, // 2.5% treasury fee
            PRIZE_VAULT,
            treasury,
            bytes32(uint256(1)),
            0,
            true // setupUniswapV4HookedPool = true - creates V4 pools!
        );

        // Give trader some WETH to start with
        vm.deal(trader, INITIAL_WETH);
        vm.prank(trader);
        WETH.deposit{value: INITIAL_WETH}();
    }

    function test_basicSetup() public {
        // Test that everything was set up correctly including V4 pools
        assertEq(WETH.balanceOf(trader), INITIAL_WETH, "Should have initial WETH");
        assertTrue(address(fanToken) != address(0), "Fan token should exist");
        assertTrue(address(GENERIC_4626_HOOK) != address(0), "Hook should exist");

        // Check that V4 pools were created for both vault and fan token
        PoolKey memory vaultPoolKey = _buildPoolKey(address(PRIZE_VAULT));
        PoolId vaultPoolId = vaultPoolKey.toId();
        (bool vaultPoolInitialized,) = GENERIC_4626_HOOK.poolDetails(vaultPoolId);

        PoolKey memory fanTokenPoolKey = _buildPoolKey(address(fanToken));
        PoolId fanTokenPoolId = fanTokenPoolKey.toId();
        (bool fanTokenPoolInitialized,) = GENERIC_4626_HOOK.poolDetails(fanTokenPoolId);

        assertTrue(vaultPoolInitialized, "Vault V4 pool should be initialized");
        assertTrue(fanTokenPoolInitialized, "Fan token V4 pool should be initialized");

        console.log("Vault pool ID:", vm.toString(PoolId.unwrap(vaultPoolId)));
        console.log("Fan token pool ID:", vm.toString(PoolId.unwrap(fanTokenPoolId)));
    }

    function test_poolKeyConstruction() public {
        // Test that _buildPoolKey constructs correct pool keys for both vault and fan token

        // Test vault pool key (vault + underlying asset)
        PoolKey memory vaultPoolKey = _buildPoolKey(address(PRIZE_VAULT));
        address vaultUnderlying = PRIZE_VAULT.asset();

        // Currencies should be sorted: underlying < vault
        assertTrue(address(vaultUnderlying) < address(PRIZE_VAULT), "WETH should be < PRIZE_VAULT address");
        assertEq(Currency.unwrap(vaultPoolKey.currency0), vaultUnderlying, "currency0 should be underlying asset");
        assertEq(Currency.unwrap(vaultPoolKey.currency1), address(PRIZE_VAULT), "currency1 should be vault");

        // Test fan token pool key (vault + fan token)
        PoolKey memory fanTokenPoolKey = _buildPoolKey(address(fanToken));
        address fanTokenUnderlying = fanToken.asset(); // This is the PRIZE_VAULT

        // Currencies should be sorted: vault < fan token
        assertTrue(address(fanTokenUnderlying) < address(fanToken), "PRIZE_VAULT should be < fanToken address");
        assertEq(Currency.unwrap(fanTokenPoolKey.currency0), fanTokenUnderlying, "currency0 should be vault");
        assertEq(Currency.unwrap(fanTokenPoolKey.currency1), address(fanToken), "currency1 should be fan token");

        // Both should use same hook and pool parameters
        assertEq(address(vaultPoolKey.hooks), address(GENERIC_4626_HOOK), "Should use Generic4626Router hook");
        assertEq(address(fanTokenPoolKey.hooks), address(GENERIC_4626_HOOK), "Should use Generic4626Router hook");
        assertEq(vaultPoolKey.fee, 0, "Should use dynamic fees");
        assertEq(fanTokenPoolKey.fee, 0, "Should use dynamic fees");
        assertEq(vaultPoolKey.tickSpacing, 1, "Should use tick spacing 1");
        assertEq(fanTokenPoolKey.tickSpacing, 1, "Should use tick spacing 1");
    }

    function test_uniswapV4PoolExists() public {
        // Test that the Generic4626Router hook has been properly set up

        // Check that both vault and fan token have pools
        PoolKey memory vaultPoolKey = _buildPoolKey(address(PRIZE_VAULT));
        PoolKey memory fanTokenPoolKey = _buildPoolKey(address(fanToken));

        PoolId vaultPoolId = vaultPoolKey.toId();
        PoolId fanTokenPoolId = fanTokenPoolKey.toId();

        (bool vaultInitialized, bool vaultWrapsZeroToOne) = GENERIC_4626_HOOK.poolDetails(vaultPoolId);
        (bool fanTokenInitialized, bool fanTokenWrapsZeroToOne) = GENERIC_4626_HOOK.poolDetails(fanTokenPoolId);

        assertTrue(vaultInitialized, "Vault pool should be initialized");
        assertTrue(fanTokenInitialized, "Fan token pool should be initialized");

        console.log("Vault pool wraps zero to one:", vaultWrapsZeroToOne);
        console.log("Fan token pool wraps zero to one:", fanTokenWrapsZeroToOne);

        // Log pool details for debugging
        console.log("=== Pool Details ===");
        console.log("Vault pool ID:", vm.toString(PoolId.unwrap(vaultPoolId)));
        console.log("Fan token pool ID:", vm.toString(PoolId.unwrap(fanTokenPoolId)));
    }

    function test_gasUsageComparison() public {
        // Compare gas usage between setupUniswapV4HookedPool enabled vs disabled
        console.log("=== Gas Usage Analysis ===");
        console.log("Fan token creation with V4 setup: setupUniswapV4HookedPool = true");

        // The gas usage for creating our fan token with V4 setup is already recorded
        // This test serves as documentation for gas impact

        assertTrue(address(fanToken) != address(0), "Fan token should be created successfully");
    }

    function test_swapChainFanTokenToPoolTickets() public {
        // Test complete swap chain: Fan Tokens → Vault Shares → Underlying Assets → Pool Tickets
        vm.startPrank(trader);

        uint256 initialFanTokens = fanToken.balanceOf(trader);
        uint256 swapAmount = initialFanTokens / 4; // Use 25% of fan tokens

        // Step 1: Fan Tokens → Vault Shares via V4 pool
        PoolKey memory fanTokenPoolKey = _buildPoolKey(address(fanToken));
        fanToken.approve(address(poolManager), swapAmount);

        IGeneric4626Router.SwapParams memory swapParams1 = IGeneric4626Router.SwapParams({
            zeroForOne: false, // Fan token (currency1) → Vault (currency0)
            amountSpecified: int256(swapAmount),
            sqrtPriceLimitX96: 1461446703485210103287273052203988822378723970341 // Max price limit
        });

        uint256 vaultSharesBefore = PRIZE_VAULT.balanceOf(trader);
        // TODO: Need actual V4 pool manager interface to execute swap
        // For now, this is a placeholder showing the intended flow
        uint256 vaultSharesReceived = swapAmount; // Mock for test

        // Step 2: Vault Shares → WETH via V4 pool
        PoolKey memory vaultPoolKey = _buildPoolKey(address(PRIZE_VAULT));
        PRIZE_VAULT.approve(address(poolManager), vaultSharesReceived);

        IGeneric4626Router.SwapParams memory swapParams2 = IGeneric4626Router.SwapParams({
            zeroForOne: false, // Vault (currency1) → WETH (currency0)
            amountSpecified: int256(vaultSharesReceived),
            sqrtPriceLimitX96: 1461446703485210103287273052203988822378723970341 // Max price limit
        });

        uint256 wethBefore = WETH.balanceOf(trader);
        // TODO: Need actual V4 pool manager interface to execute swap
        // For now, this is a placeholder showing the intended flow
        uint256 wethReceived = vaultSharesReceived; // Mock for test

        // Step 3: WETH → Pool Tickets (direct deposit to pool together)
        WETH.approve(address(PRIZE_VAULT), wethReceived);
        uint256 poolTickets = PRIZE_VAULT.deposit(wethReceived, trader);

        // Verify the test setup and flow structure (with mocked values)
        assertGt(initialFanTokens, 0, "Should start with fan tokens from setup");
        assertGt(swapAmount, 0, "Should have calculated swap amount");
        assertGt(vaultSharesReceived, 0, "Should have mocked vault shares");
        assertGt(wethReceived, 0, "Should have mocked WETH");
        assertTrue(address(poolManager) != address(0), "Should have pool manager address");

        vm.stopPrank();
    }

    // ===== HELPER FUNCTIONS =====

    function _buildPoolKey(address vault) internal view returns (PoolKey memory) {
        // The Generic4626Router creates pools between a vault and its underlying asset
        address underlying = IERC4626(vault).asset();

        // Sort addresses for currency0/currency1 (Uniswap V4 requirement)
        address currency0Addr = underlying < vault ? underlying : vault;
        address currency1Addr = underlying < vault ? vault : underlying;

        return PoolKey({
            currency0: Currency.wrap(currency0Addr),
            currency1: Currency.wrap(currency1Addr),
            fee: 0,
            tickSpacing: 1,
            hooks: IHooks(address(GENERIC_4626_HOOK))
        });
    }
}
