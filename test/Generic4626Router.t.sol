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
    IUniversalRouter constant UNIVERSAL_ROUTER = IUniversalRouter(0x6fF5693b99212Da76ad316178A184AB56D299b43);
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

        // NOTE: fanToken.deposit() CAN get fan tokens (that works), but factory creation already gives us fan tokens
        // We're testing the hook trading functionality, not the deposit flow

        vm.stopPrank();
    }

    function test_v4_pools_are_properly_initialized() public {
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

        // Factory creation with INITIAL_WETH should have given trader fan tokens
        assertGt(fanToken.balanceOf(trader), 0, "Setup should have given trader fan tokens");
    }

    function test_withdrawing_using_the_hook() public {
        // Setup should have given trader fan tokens
        uint256 initialFanTokens = fanToken.balanceOf(trader);
        uint256 initialVaultTokens = PRIZE_VAULT.balanceOf(trader);

        assertGt(initialFanTokens, 0, "Setup should have given trader fan tokens");

        vm.startPrank(trader);

        // Approve Universal Router to spend fan tokens
        fanToken.approve(address(UNIVERSAL_ROUTER), initialFanTokens / 2);

        // Build the pool key for Fan Token <-> Prize Vault pool
        PoolKey memory fanTokenPoolKey = _buildPoolKey(address(fanToken));

        // Encode V4 swap command for Fan Tokens -> Prize Vault tokens
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));

        // Prepare swap parameters
        bool zeroForOne = address(fanToken) < address(PRIZE_VAULT);

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(
            fanTokenPoolKey,
            zeroForOne,
            -int256(initialFanTokens / 2), // exactAmountIn (negative for exact input)
            zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1,
            bytes("")
        );

        // Execute swap via Universal Router
        UNIVERSAL_ROUTER.execute(commands, inputs, block.timestamp + 300);

        // Verify the swap worked
        uint256 finalFanTokens = fanToken.balanceOf(trader);
        uint256 finalVaultTokens = PRIZE_VAULT.balanceOf(trader);

        assertLt(finalFanTokens, initialFanTokens, "Should have spent fan tokens");
        assertGt(finalVaultTokens, initialVaultTokens, "Should have received vault tokens");

        vm.stopPrank();
    }

    function test_multihop_withdrawing_using_the_hook() public {
        // Setup should have given trader fan tokens
        uint256 initialFanTokens = fanToken.balanceOf(trader);
        uint256 initialWETH = WETH.balanceOf(trader);

        assertGt(initialFanTokens, 0, "Setup should have given trader fan tokens");

        vm.startPrank(trader);

        // Approve Universal Router to spend fan tokens
        fanToken.approve(address(UNIVERSAL_ROUTER), initialFanTokens / 2);

        // Multihop swap: fan tokens -> prize vault tokens -> WETH via Universal Router
        PoolKey memory fanTokenPoolKey = _buildPoolKey(address(fanToken));
        PoolKey memory vaultPoolKey = _buildPoolKey(address(PRIZE_VAULT));

        // Encode two V4 swap commands for multihop
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP), uint8(Commands.V4_SWAP));

        // First hop: fan tokens -> prize vault tokens
        bool fanZeroForOne = address(fanToken) < address(PRIZE_VAULT);
        // Second hop: prize vault tokens -> WETH
        bool vaultZeroForOne = address(WETH) < address(PRIZE_VAULT);

        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(
            fanTokenPoolKey,
            fanZeroForOne,
            -int256(initialFanTokens / 2), // exactAmountIn for first hop
            fanZeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1,
            bytes("")
        );
        inputs[1] = abi.encode(
            vaultPoolKey,
            vaultZeroForOne,
            int256(0), // exactAmountOut - use all from previous hop
            vaultZeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1,
            bytes("")
        );

        // Execute multihop swap via Universal Router
        UNIVERSAL_ROUTER.execute(commands, inputs, block.timestamp + 300);

        // Verify the multihop swap worked
        uint256 finalFanTokens = fanToken.balanceOf(trader);
        uint256 finalWETH = WETH.balanceOf(trader);

        assertLt(finalFanTokens, initialFanTokens, "Should have spent fan tokens");
        assertGt(finalWETH, initialWETH, "Should have received WETH");

        vm.stopPrank();
    }

    function test_depositing_using_the_hook() public {
        uint256 initialWETH = WETH.balanceOf(trader);
        uint256 initialVaultTokens = PRIZE_VAULT.balanceOf(trader);

        vm.startPrank(trader);

        // Approve Universal Router to spend WETH
        WETH.approve(address(UNIVERSAL_ROUTER), TRADE_AMOUNT);

        // Build the pool key for WETH <-> Prize Vault pool
        PoolKey memory vaultPoolKey = _buildPoolKey(address(PRIZE_VAULT));

        // Encode V4 swap command for WETH -> Prize Vault tokens
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));

        // Prepare swap parameters
        bool zeroForOne = address(WETH) < address(PRIZE_VAULT);

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(
            vaultPoolKey,
            zeroForOne,
            -int256(TRADE_AMOUNT), // exactAmountIn (negative for exact input)
            zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1,
            bytes("")
        );

        // Execute swap via Universal Router
        UNIVERSAL_ROUTER.execute(commands, inputs, block.timestamp + 300);

        vm.stopPrank();

        // Verify the swap worked
        uint256 finalWETH = WETH.balanceOf(trader);
        uint256 finalVaultTokens = PRIZE_VAULT.balanceOf(trader);

        assertLt(finalWETH, initialWETH, "Should have spent WETH");
        assertGt(finalVaultTokens, initialVaultTokens, "Should have received vault tokens");
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
