// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {IERC20, IERC4626, IWETH9} from "../src/FanToken.sol";
import {FanToken, FanTokenFactory} from "../src/FanTokenFactory.sol";
import {IGeneric4626Router} from "../src/interfaces/IGeneric4626Router.sol";
import {IV4Router} from "v4-periphery/src/interfaces/IV4Router.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";

// For now, use interface since V4_SWAP doesn't exist in current Commands library
interface IUniversalRouter {
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable;
}

import {Commands} from "@uniswap/universal-router/contracts/libraries/Commands.sol";

interface IPermit2 {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}
import {PoolIdLibrary, PoolId} from "v4-core/src/types/PoolId.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";

using PoolIdLibrary for PoolKey;

/**
 * @title Generic4626Router Integration Test
 * @notice Tests that Generic4626Router hook properly creates V4 pools
 * @dev This test verifies the Uniswap V4 integration without attempting actual swaps
 */
contract Generic4626RouterTest is Test {
    using StateLibrary for IPoolManager;
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

    /// @notice create a fan token and give the trader some of it
    function setUp() public {
        // Create test accounts
        trader = makeAddr("trader");
        treasury = address(0);

        // Deploy factory with the Generic4626Router hook
        factory = new FanTokenFactory(WETH, GENERIC_ROUTER);

        // Get the pool manager from the Generic4626Router
        poolManager = IPoolManager(GENERIC_ROUTER.poolManager());

        // Create a fan token for our prize vault - this sets up V4 pools
        // this must be done as the contract because we do NOT want the trader to be the owner
        fanToken = factory.create{value: INITIAL_WETH}(
            "Prize Vault Fan Token",
            "PVF",
            0,
            0,
            PRIZE_VAULT,
            treasury,
            bytes32(0),
            INITIAL_WETH,
            true // setupUniswapV4HookedPool = true - creates V4 pools!
        );

        console.log("sponsor balance", fanToken.balanceOfSponsor(address(this)));

        fanToken.sponsorTransfer(trader, INITIAL_WETH);

        hoax(trader, INITIAL_WETH * 2);

        // Give trader some WETH to start with
        WETH.deposit{value: INITIAL_WETH}();

        // Approve tokens for Universal Router
        // TODO: we need to read more about how WETH/ETH work on the universal router
        PRIZE_VAULT.approve(address(UNIVERSAL_ROUTER), type(uint256).max);
        fanToken.approve(address(UNIVERSAL_ROUTER), type(uint256).max);
    }

    function test_constants() public view {
        assertTrue(address(fanToken) != address(0), "Fan token should exist");
        assertTrue(address(GENERIC_ROUTER) != address(0), "Router should exist");
    }

    function test_setup_gave_fan_tokens() public view {
        assertEq(WETH.balanceOf(trader), INITIAL_WETH, "Should have initial WETH");
        assertGt(fanToken.balanceOf(trader), 0, "Should have a nonzero balance");
        assertEq(fanToken.balanceOfUnderlying(trader), INITIAL_WETH, "Should have the right underlying value");
    }

    function test_v4_pools_are_properly_initialized() public view {
        // Test that everything was set up correctly including V4 pools

        // Check that V4 pools were created for both vault and fan token
        PoolKey memory vaultPoolKey = _buildPoolKey(address(PRIZE_VAULT));
        PoolId vaultPoolId = vaultPoolKey.toId();
        // Actually check if pools were initialized using pool manager
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(vaultPoolId);
        bool vaultPoolInitialized = sqrtPriceX96 != 0;

        PoolKey memory fanTokenPoolKey = _buildPoolKey(address(fanToken));
        PoolId fanTokenPoolId = fanTokenPoolKey.toId();
        (uint160 sqrtPriceX96Fan,,,) = poolManager.getSlot0(fanTokenPoolId);
        bool fanTokenPoolInitialized = sqrtPriceX96Fan != 0;

        assertTrue(vaultPoolInitialized, "Vault V4 pool should be initialized");
        assertTrue(fanTokenPoolInitialized, "Fan token V4 pool should be initialized");

        // Verify pool IDs are non-zero (valid)
        assertTrue(PoolId.unwrap(vaultPoolId) != bytes32(0), "Vault pool ID should be non-zero");
        assertTrue(PoolId.unwrap(fanTokenPoolId) != bytes32(0), "Fan token pool ID should be non-zero");

        // Factory creation with INITIAL_WETH should have given trader fan tokens
        assertGt(fanToken.balanceOf(trader), 0, "Setup should have given trader fan tokens");
    }

    function test_withdrawing_using_the_hook() public {
        // Test swapping fan tokens for vault tokens through Universal Router
        uint256 initialFanTokens = fanToken.balanceOf(trader);
        uint256 initialVaultTokens = PRIZE_VAULT.balanceOf(trader);
        uint128 swapAmount = uint128(initialFanTokens / 2);

        assertGt(initialFanTokens, 0, "Setup should have given trader fan tokens");

        vm.startPrank(trader);

        // Set up Permit2 approvals per official Universal Router docs
        address permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
        fanToken.approve(permit2, type(uint256).max);
        IPermit2(permit2).approve(
            address(fanToken),
            address(UNIVERSAL_ROUTER), 
            uint160(swapAmount),
            uint48(block.timestamp + 3600)
        );

        // Build the pool key
        PoolKey memory poolKey = _buildPoolKey(address(fanToken));

        // Use Universal Router with proper V4_SWAP command 
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        
        // Encode V4Router actions per official docs
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );

        // Prepare parameters - three parameters for three actions
        bytes[] memory params = new bytes[](3);
        
        // Action 1: SWAP_EXACT_IN_SINGLE parameters
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: poolKey,
                zeroForOne: address(fanToken) > address(PRIZE_VAULT),
                amountIn: swapAmount,
                amountOutMinimum: 0,
                hookData: bytes("")
            })
        );
        
        // Action 2: SETTLE_ALL parameters 
        params[1] = abi.encode(
            address(fanToken), // currency to settle
            swapAmount // max amount to settle
        );
        
        // Action 3: TAKE_ALL parameters
        params[2] = abi.encode(
            address(PRIZE_VAULT), // currency to take
            uint256(0) // minimum amount (0 = take all)
        );

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);

        // Execute via Universal Router
        UNIVERSAL_ROUTER.execute(commands, inputs, block.timestamp + 300);

        vm.stopPrank();

        // Verify the swap worked - assert actual traded values
        uint256 finalFanTokens = fanToken.balanceOf(trader);
        uint256 finalVaultTokens = PRIZE_VAULT.balanceOf(trader);

        assertEq(finalFanTokens, initialFanTokens - swapAmount, "Should have spent exact fan token amount");
        assertGt(finalVaultTokens, initialVaultTokens, "Should have received vault tokens from hook conversion");
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
        PoolKey memory poolKey = _buildPoolKey(address(PRIZE_VAULT));

        // Encode V4 swap command
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));

        // Encode V4Router actions sequence
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );

        // Determine swap direction (WETH -> Prize Vault)
        bool zeroForOne = address(WETH) < address(PRIZE_VAULT);

        // Prepare parameters for each action
        bytes[] memory params = new bytes[](3);
        
        // Action 1: SWAP_EXACT_IN_SINGLE parameters
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: poolKey,
                zeroForOne: zeroForOne,
                amountIn: uint128(TRADE_AMOUNT),
                amountOutMinimum: 0, // Accept any amount for testing
                hookData: bytes("")
            })
        );
        
        // Action 2: SETTLE_ALL parameters
        params[1] = abi.encode(
            zeroForOne ? poolKey.currency0 : poolKey.currency1,
            uint128(TRADE_AMOUNT)
        );
        
        // Action 3: TAKE_ALL parameters
        params[2] = abi.encode(
            zeroForOne ? poolKey.currency1 : poolKey.currency0,
            uint128(0)
        );

        // Combine actions and params into inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);

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
