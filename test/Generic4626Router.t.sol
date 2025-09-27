// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {IERC4626, IWETH9} from "../src/FanToken.sol";
import {FanToken, FanTokenFactory} from "../src/FanTokenFactory.sol";
import {Generic4626Router} from "../src/interfaces/Generic4626Router.sol";
import {PoolIdLibrary, PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
// import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
// import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
// import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {IUniversalRouter} from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
import {Commands} from "@uniswap/universal-router/contracts/libraries/Commands.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

// using PoolIdLibrary for PoolKey;
using CurrencyLibrary for Currency;

/**
 * @title Generic4626Router Integration Test
 * @notice Tests that Generic4626Router hook properly creates V4 pools
 * @dev This test verifies the Uniswap V4 integration without attempting actual swaps
 */
contract Generic4626RouterTest is Test {
    // using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;
    using SafeCast for uint256;

    // Core contracts
    IWETH9 constant WETH = IWETH9(payable(0x4200000000000000000000000000000000000006));
    IERC4626 constant PRIZE_VAULT = IERC4626(0x4E42f783db2D0C5bDFf40fDc66FCAe8b1Cda4a43);
    Generic4626Router constant GENERIC_4626_ROUTER = Generic4626Router(0xD60a6A0f0D5E3Fd451449C7256BbbDC59561e888);
    IUniversalRouter constant UNIVERSAL_ROUTER = IUniversalRouter(payable(0x6fF5693b99212Da76ad316178A184AB56D299b43));
    IPermit2 constant PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    IPoolManager poolManager;

    // Test contracts
    FanTokenFactory factory;
    FanToken fanToken;

    // Test accounts
    address trader;
    address treasury;

    // Trade amounts
    uint256 constant INITIAL_WETH = 1 ether;
    uint256 constant TRADE_AMOUNT = 0.5 ether;

    /// @notice create a fan token and give the trader some of it
    function setUp() public {
        // Create test accounts
        trader = makeAddr("trader");
        treasury = address(0);

        // Deploy factory with the Generic4626Router hook
        factory = new FanTokenFactory(WETH, GENERIC_4626_ROUTER);

        // Get the pool manager from the Generic4626Router
        poolManager = IPoolManager(GENERIC_4626_ROUTER.poolManager());

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

        assertEq(
            fanToken.balanceOfSponsorAssets(address(this)),
            INITIAL_WETH,
            "creator should receive sponsor assets from initial deposit"
        );

        fanToken.sponsorTransfer(trader, INITIAL_WETH);

        assertEq(fanToken.balanceOfSponsorAssets(address(this)), 0, "creator sponsorship should transfer to trader");

        startHoax(trader, INITIAL_WETH * 2);

        // Give trader some WETH to start with
        WETH.deposit{value: INITIAL_WETH}();

        // Approve tokens for Universal Router using Permit2 pattern from official docs
        WETH.approve(address(PERMIT2), type(uint256).max);
        PERMIT2.approve(address(WETH), address(UNIVERSAL_ROUTER), type(uint160).max, type(uint48).max);

        PRIZE_VAULT.approve(address(PERMIT2), type(uint256).max);
        PERMIT2.approve(address(PRIZE_VAULT), address(UNIVERSAL_ROUTER), type(uint160).max, type(uint48).max);

        fanToken.approve(address(PERMIT2), type(uint256).max);
        PERMIT2.approve(address(fanToken), address(UNIVERSAL_ROUTER), type(uint160).max, type(uint48).max);
    }

    function test_constants() public view {
        assertTrue(address(fanToken) != address(0), "Fan token should exist");
        assertTrue(address(GENERIC_4626_ROUTER) != address(0), "Router should exist");
    }

    function test_setup_gave_fan_tokens() public view {
        assertEq(WETH.balanceOf(trader), INITIAL_WETH, "Should have initial WETH");
        assertGt(fanToken.balanceOf(trader), 0, "Should have a nonzero balance");
        assertEq(fanToken.balanceOfUnderlying(trader), INITIAL_WETH, "Should have the right underlying value");
    }

    /// @dev Test that V4 pools with the 4626 hook are set up
    function test_v4_pools_are_properly_initialized() public view {
        // prize vault checks
        PoolKey memory vaultPoolKey = _buildPoolKey(address(PRIZE_VAULT));

        PoolId vaultPoolId = vaultPoolKey.toId();
        assertTrue(PoolId.unwrap(vaultPoolId) != bytes32(0), "Vault pool ID should be non-zero");

        (bool vaultPoolInitialized,) = GENERIC_4626_ROUTER.poolDetails(vaultPoolId);

        assertTrue(vaultPoolInitialized, "Vault V4 pool should be initialized");

        // fan token checks
        PoolKey memory fanTokenPoolKey = _buildPoolKey(address(fanToken));

        PoolId fanTokenPoolId = fanTokenPoolKey.toId();
        assertTrue(PoolId.unwrap(fanTokenPoolId) != bytes32(0), "Fan token pool ID should be non-zero");

        (bool fanTokenPoolInitialized,) = GENERIC_4626_ROUTER.poolDetails(fanTokenPoolId);

        assertTrue(fanTokenPoolInitialized, "Fan token V4 pool should be initialized");
    }

    /// @notice Test swapping fan tokens for vault tokens through Universal Router
    /// @dev [Docs for swapping](https://docs.uniswap.org/contracts/v4/guides/swap-routing)
    /// @dev [Minimal Router instead of Universal Router](https://github.com/uniswapfoundation/foundational-hooks/blob/main/test/utils/MinimalRouter.sol)
    function test_withdrawing_using_the_hook() public {
        vm.startPrank(trader);

        uint256 initialFanTokens = fanToken.balanceOf(trader);
        uint256 initialVaultTokens = PRIZE_VAULT.balanceOf(trader);

        assertGt(initialFanTokens, 0, "Setup should have given trader fan tokens");
        assertGe(initialFanTokens, TRADE_AMOUNT * 2, "initial balance should cover configured trade size");

        PoolKey memory fanTokenPoolKey = _buildPoolKey(address(fanToken));

        address currency0 = Currency.unwrap(fanTokenPoolKey.currency0);
        address currency1 = Currency.unwrap(fanTokenPoolKey.currency1);

        address expectedCurrency0 = address(PRIZE_VAULT) < address(fanToken) ? address(PRIZE_VAULT) : address(fanToken);
        address expectedCurrency1 = expectedCurrency0 == address(PRIZE_VAULT) ? address(fanToken) : address(PRIZE_VAULT);

        console.log("currency0", currency0);
        console.log("currency1", currency1);

        assertEq(currency0, expectedCurrency0, "currency0 ordering mismatch");
        assertEq(currency1, expectedCurrency1, "currency1 ordering mismatch");

        // PoolId fanTokenPoolId = fanTokenPoolKey.toId();

        // Determine swap direction: fan tokens -> vault tokens
        // (bool fanTokenPoolInitialized, bool wrapZeroForOne) = GENERIC_4626_ROUTER.poolDetails(fanTokenPoolId);

        bool zeroForOne;
        if (currency0 == address(fanToken)) {
            zeroForOne = true;
        } else {
            zeroForOne = false;
        }
        assertEq(zeroForOne, currency0 == address(fanToken), "zeroForOne should reflect address ordering");

        // Following official docs exactly - encode the Universal Router uniswap v4 swap command
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes[] memory inputs = new bytes[](1);

        // like the official docs, except we send the input first to avoid PoolManager token balance issues
        bytes memory actions =
            abi.encodePacked(uint8(Actions.SETTLE), uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.TAKE_ALL));

        // Prepare parameters for each action exactly as in docs (except the settle is now first)
        bytes[] memory params = new bytes[](3);

        params[0] = abi.encode(
            zeroForOne ? fanTokenPoolKey.currency0 : fanTokenPoolKey.currency1, // input currency
            TRADE_AMOUNT, // amountIn. some docs made me think this should be uint128, but V4Router.sol SETTLE looks different
            true // payerIsUser (TODO: what is this?) if false, it uses the pool manager. if true, it uses msg.sender
        );
        params[1] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: fanTokenPoolKey,
                zeroForOne: zeroForOne,
                amountIn: TRADE_AMOUNT.toUint128(),
                amountOutMinimum: uint128(0),
                hookData: bytes("")
            })
        );
        params[2] = abi.encode(
            zeroForOne ? fanTokenPoolKey.currency1 : fanTokenPoolKey.currency0, // output currency
            uint128(0) // minAmountOut. TODO: how should we calculate this in production?
        );

        // Combine actions and params into inputs exactly as in docs
        inputs[0] = abi.encode(actions, params);

        // Execute swap via Universal Router
        UNIVERSAL_ROUTER.execute(commands, inputs, block.timestamp + 300);

        // Verify the swap worked
        uint256 finalFanTokens = fanToken.balanceOf(trader);
        uint256 finalVaultTokens = PRIZE_VAULT.balanceOf(trader);

        assertEq(finalFanTokens + TRADE_AMOUNT, initialFanTokens, "fan token balance mismatch");
        assertEq(finalVaultTokens, initialVaultTokens + TRADE_AMOUNT, "vault balance mismatch");
    }

    /*
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

        
    }
    */

    /*
    function test_depositing_using_the_hook() public {
        uint256 initialWETH = WETH.balanceOf(trader);
        uint256 initialVaultTokens = PRIZE_VAULT.balanceOf(trader);

        vm.startPrank(trader);

        // Set up Permit2 approvals for Universal Router
        fanToken.approve(address(PERMIT2), type(uint256).max);
        PERMIT2.approve(address(fanToken), address(UNIVERSAL_ROUTER), type(uint160).max, type(uint48).max);

        // Build the pool key for Fan Token <-> Prize Vault pool  
        PoolKey memory poolKey = _buildPoolKey(address(fanToken));

        // Encode V4 swap command
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));

        // SETTLE → SWAP_EXACT_IN_SINGLE → TAKE_ALL sequence as requested
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SETTLE),
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.TAKE_ALL)
        );

        // Determine swap direction (Fan Token -> Prize Vault)
        bool zeroForOne = address(fanToken) < address(PRIZE_VAULT);

        // Prepare parameters for each action
        bytes[] memory params = new bytes[](3);
        
        // Action 1: SETTLE - settle fan tokens into the pool manager  
        params[0] = abi.encode(
            address(fanToken),      // currency address
            uint256(TRADE_AMOUNT),  // amount to settle
            true                    // payerIsUser - user pays via Permit2
        );
        
        // Action 2: SWAP_EXACT_IN_SINGLE parameters
        params[1] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: poolKey,
                zeroForOne: zeroForOne,
                amountIn: uint128(TRADE_AMOUNT),
                amountOutMinimum: 0, // Accept any amount for testing
                hookData: bytes("")
            })
        );
        
        // Action 3: TAKE_ALL - take all output tokens to user
        params[2] = abi.encode(
            Currency.unwrap(zeroForOne ? poolKey.currency0 : poolKey.currency1),  // currency address 
            uint256(type(uint256).max)  // amount (max = take all)
        );

        // Combine actions and params into inputs - V4_SWAP expects them encoded together
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);

        // Execute swap via Universal Router
        UNIVERSAL_ROUTER.execute(commands, inputs, block.timestamp + 300);

        // Verify the swap worked
        uint256 finalWETH = WETH.balanceOf(trader);
        uint256 finalVaultTokens = PRIZE_VAULT.balanceOf(trader);

        assertLt(finalWETH, initialWETH, "Should have spent WETH");
        assertGt(finalVaultTokens, initialVaultTokens, "Should have received vault tokens");
    }
    */

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
            hooks: IHooks(address(GENERIC_4626_ROUTER))
        });
    }
}
