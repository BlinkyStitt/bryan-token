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
    IGeneric4626Router constant GENERIC_ROUTER = IGeneric4626Router(0xD60a6A0f0D5E3Fd451449C7256BbbDC59561e888);

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

        vm.startPrank(trader);

        // Give trader some WETH to start with
        vm.deal(trader, INITIAL_WETH * 2);
        WETH.deposit{value: INITIAL_WETH * 2}();

        WETH.approve(address(factory), type(uint256).max);

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

        console.log("Vault pool ID:", vm.toString(PoolId.unwrap(vaultPoolId)));
        console.log("Fan token pool ID:", vm.toString(PoolId.unwrap(fanTokenPoolId)));
    }

    function test_hook_details() public {
        // Test that the Generic4626Router hook has been properly set up

        // Check that both vault and fan token have pools
        PoolKey memory vaultPoolKey = _buildPoolKey(address(PRIZE_VAULT));
        PoolKey memory fanTokenPoolKey = _buildPoolKey(address(fanToken));

        PoolId vaultPoolId = vaultPoolKey.toId();
        PoolId fanTokenPoolId = fanTokenPoolKey.toId();

        (bool vaultInitialized, bool vaultWrapsZeroToOne) = GENERIC_ROUTER.poolDetails(vaultPoolId);
        (bool fanTokenInitialized, bool fanTokenWrapsZeroToOne) = GENERIC_ROUTER.poolDetails(fanTokenPoolId);

        assertTrue(vaultInitialized, "Vault pool should be initialized");
        assertTrue(fanTokenInitialized, "Fan token pool should be initialized");

        console.log("Vault pool wraps zero to one:", vaultWrapsZeroToOne);
        console.log("Fan token pool wraps zero to one:", fanTokenWrapsZeroToOne);

        // Log pool details for debugging
        console.log("=== Pool Details ===");
        console.log("Vault pool ID:", vm.toString(PoolId.unwrap(vaultPoolId)));
        console.log("Fan token pool ID:", vm.toString(PoolId.unwrap(fanTokenPoolId)));
    }

    function test_withdrawing_using_the_hook() public {
        // TODO: use the pool manager/uniswap v4 router to trade the fan token balance you have back to pool together tickets
        revert("write this");
    }

    function test_multihop_withdrawing_using_the_hook() public {
        // TODO: use the pool manager/uniswap v4 router to trade the fan token balance you have back to WETH.
        revert("write this");
    }

    function test_depositing_using_the_hook() public {
        // you already have a weth balance
        // TODO: use the pool manager/uniswap v4 router to trade WETH into pool together tickets. then trade pool together tickets back to WETH. i think this can be done in one transaction. just two pools traded against
        revert("write this");
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
