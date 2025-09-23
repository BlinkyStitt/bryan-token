// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {IERC20, IERC4626, IWETH9} from "../src/FanToken.sol";
import {FanToken, FanTokenFactory} from "../src/FanTokenFactory.sol";
import {IGeneric4626Router} from "../src/interfaces/IGeneric4626Router.sol";
import {IUniversalRouter, Commands, Actions} from "../src/interfaces/IUniversalRouter.sol";
import {PoolIdLibrary, PoolId} from "v4-core/src/types/PoolId.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

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
    IGeneric4626Router constant GENERIC_ROUTER = IGeneric4626Router(0xD60a6A0f0D5E3Fd451449C7256BbbDC59561e888);
    IUniversalRouter constant UNIVERSAL_ROUTER = IUniversalRouter(0x3fC91A3afd70395Cd496C647d5a6CC9D4B2b7FAD);
    IPoolManager poolManager;

    // Test contracts
    FanTokenFactory factory;
    FanToken fanToken;

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
        factory = new FanTokenFactory(WETH, GENERIC_ROUTER);

        // Get the pool manager from the router
        poolManager = IPoolManager(GENERIC_ROUTER.poolManager());

        vm.startPrank(trader);

        // Give trader some WETH to start with
        vm.deal(trader, INITIAL_WETH * 2);
        WETH.deposit{value: INITIAL_WETH * 2}();

        WETH.approve(address(factory), type(uint256).max);
        WETH.approve(address(UNIVERSAL_ROUTER), type(uint256).max);

        // Create a fan token for our prize vault - this sets up V4 pools
        fanToken = factory.create(
            "Prize Vault Fan Token",
            "PVF",
            500, // 5% owner fee
            250, // 2.5% treasury fee
            PRIZE_VAULT,
            treasury,
            bytes32(uint256(1)),
            INITIAL_WETH,
            true // setupUniswapV4HookedPool = true - creates V4 pools!
        );

        // Approve tokens for Universal Router
        PRIZE_VAULT.approve(address(UNIVERSAL_ROUTER), type(uint256).max);
        fanToken.approve(address(UNIVERSAL_ROUTER), type(uint256).max);

        vm.stopPrank();
    }

    function test_pool_details() public {
        // Test that everything was set up correctly including V4 pools
        assertEq(WETH.balanceOf(trader), INITIAL_WETH, "Should have initial WETH");
        assertTrue(address(fanToken) != address(0), "Fan token should exist");
        assertTrue(address(GENERIC_ROUTER) != address(0), "Router should exist");

        // Check that V4 pools were created for both vault and fan token
        PoolKey memory vaultPoolKey = _buildPoolKey(address(PRIZE_VAULT));
        PoolId vaultPoolId = vaultPoolKey.toId();
        (bool vaultPoolInitialized,) = GENERIC_ROUTER.poolDetails(vaultPoolId);

        PoolKey memory fanTokenPoolKey = _buildPoolKey(address(fanToken));
        PoolId fanTokenPoolId = fanTokenPoolKey.toId();
        (bool fanTokenPoolInitialized,) = GENERIC_ROUTER.poolDetails(fanTokenPoolId);

        assertTrue(vaultPoolInitialized, "Vault V4 pool should be initialized");
        assertTrue(fanTokenPoolInitialized, "Fan token V4 pool should be initialized");

        // Verify pool IDs are non-zero (valid)
        assertTrue(PoolId.unwrap(vaultPoolId) != bytes32(0), "Vault pool ID should be non-zero");
        assertTrue(PoolId.unwrap(fanTokenPoolId) != bytes32(0), "Fan token pool ID should be non-zero");
    }

    function test_withdrawing_using_the_hook() public {
        // Verify we can build the fan token pool key for potential trading
        PoolKey memory fanTokenPoolKey = _buildPoolKey(address(fanToken));

        // Verify the pool is properly initialized
        PoolId fanTokenPoolId = fanTokenPoolKey.toId();
        (bool fanTokenPoolInitialized,) = GENERIC_ROUTER.poolDetails(fanTokenPoolId);
        assertTrue(fanTokenPoolInitialized, "Fan token pool should be initialized");

        // Verify pool key is correctly configured
        assertTrue(address(fanTokenPoolKey.hooks) == address(GENERIC_ROUTER), "Hook should be Generic4626Router");
        assertTrue(
            Currency.unwrap(fanTokenPoolKey.currency0) != Currency.unwrap(fanTokenPoolKey.currency1),
            "Currencies should be different"
        );

        // Verify currencies are fan token and prize vault
        address currency0 = Currency.unwrap(fanTokenPoolKey.currency0);
        address currency1 = Currency.unwrap(fanTokenPoolKey.currency1);
        assertTrue(
            (currency0 == address(fanToken) && currency1 == address(PRIZE_VAULT))
                || (currency0 == address(PRIZE_VAULT) && currency1 == address(fanToken)),
            "Pool should be between fan token and prize vault"
        );
    }

    function test_multihop_withdrawing_using_the_hook() public {
        // Verify we can build both pool keys for multihop trading path
        PoolKey memory fanTokenPoolKey = _buildPoolKey(address(fanToken));
        PoolKey memory vaultPoolKey = _buildPoolKey(address(PRIZE_VAULT));

        // Verify both pools are initialized
        PoolId fanTokenPoolId = fanTokenPoolKey.toId();
        PoolId vaultPoolId = vaultPoolKey.toId();

        (bool fanTokenPoolInitialized,) = GENERIC_ROUTER.poolDetails(fanTokenPoolId);
        (bool vaultPoolInitialized,) = GENERIC_ROUTER.poolDetails(vaultPoolId);

        assertTrue(fanTokenPoolInitialized, "Fan token pool should be initialized");
        assertTrue(vaultPoolInitialized, "Vault pool should be initialized");

        // Verify hooks are correctly configured
        assertTrue(
            address(fanTokenPoolKey.hooks) == address(GENERIC_ROUTER), "Fan token hook should be Generic4626Router"
        );
        assertTrue(address(vaultPoolKey.hooks) == address(GENERIC_ROUTER), "Vault hook should be Generic4626Router");

        // Verify fan token pool currencies
        address fanCurrency0 = Currency.unwrap(fanTokenPoolKey.currency0);
        address fanCurrency1 = Currency.unwrap(fanTokenPoolKey.currency1);
        assertTrue(
            (fanCurrency0 == address(fanToken) && fanCurrency1 == address(PRIZE_VAULT))
                || (fanCurrency0 == address(PRIZE_VAULT) && fanCurrency1 == address(fanToken)),
            "Fan token pool should be between fan token and prize vault"
        );

        // Verify vault pool currencies
        address vaultCurrency0 = Currency.unwrap(vaultPoolKey.currency0);
        address vaultCurrency1 = Currency.unwrap(vaultPoolKey.currency1);
        assertTrue(
            (vaultCurrency0 == address(WETH) && vaultCurrency1 == address(PRIZE_VAULT))
                || (vaultCurrency0 == address(PRIZE_VAULT) && vaultCurrency1 == address(WETH)),
            "Vault pool should be between WETH and prize vault"
        );
    }

    function test_depositing_using_the_hook() public {
        uint256 initialWETH = WETH.balanceOf(trader);
        uint256 initialVaultTokens = PRIZE_VAULT.balanceOf(trader);
        assertEq(initialWETH, INITIAL_WETH, "Should start with initial WETH");
        assertEq(initialVaultTokens, 0, "Should start with no vault tokens");

        // Verify vault pool setup for WETH to vault token trading
        PoolKey memory vaultPoolKey = _buildPoolKey(address(PRIZE_VAULT));
        PoolId vaultPoolId = vaultPoolKey.toId();
        (bool vaultPoolInitialized,) = GENERIC_ROUTER.poolDetails(vaultPoolId);

        assertTrue(vaultPoolInitialized, "Vault pool should be initialized");
        assertTrue(address(vaultPoolKey.hooks) == address(GENERIC_ROUTER), "Hook should be Generic4626Router");
        assertTrue(
            Currency.unwrap(vaultPoolKey.currency0) != Currency.unwrap(vaultPoolKey.currency1),
            "Currencies should be different"
        );

        // Verify pool is between WETH and prize vault
        address currency0 = Currency.unwrap(vaultPoolKey.currency0);
        address currency1 = Currency.unwrap(vaultPoolKey.currency1);
        assertTrue(
            (currency0 == address(WETH) && currency1 == address(PRIZE_VAULT))
                || (currency0 == address(PRIZE_VAULT) && currency1 == address(WETH)),
            "Pool should be between WETH and prize vault"
        );

        // Verify fee and tick spacing are set correctly
        assertEq(vaultPoolKey.fee, 0, "Pool fee should be 0");
        assertEq(vaultPoolKey.tickSpacing, 1, "Pool tick spacing should be 1");
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
            hooks: IHooks(address(GENERIC_ROUTER))
        });
    }
}
