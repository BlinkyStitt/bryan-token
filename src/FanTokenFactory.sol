// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

// TODO: use cloneable instead of deploying a full contract every time?

import {FanToken, SafeERC20, IERC20, IERC4626, IWETH9} from "./FanToken.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

error InvalidFanToken();
error IncorrectUnderlying(address underlying);
error NoUnderlyingAssets();

contract FanTokenFactory {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;
    using CurrencyLibrary for Currency;

    /// @notice make it easy to deposit by just sending ETH
    IWETH9 public immutable WETH;

    /// @notice Uniswap V4 pool manager for creating pools
    IPoolManager public immutable POOL_MANAGER;

    /// @notice The Uniswap V4 hook contract address for handling ERC4626 tokens and their assets.
    IHooks public immutable UNISWAP_V4_HOOK;

    /// @notice enumerable set of all deployed fan tokens
    EnumerableSet.AddressSet private _deployedTokens;

    // TODO: how should we do indexes on this?
    event Created(address indexed _owner, address indexed _prizeVault, address indexed _treasury, address _token);

    constructor(IWETH9 _weth, IPoolManager _poolManager, IHooks _uniswapV4Hook) {
        WETH = _weth;
        POOL_MANAGER = _poolManager;
        UNISWAP_V4_HOOK = _uniswapV4Hook;
    }

    function create(
        string memory _name,
        string memory _symbol,
        uint256 _harvestOwnerFeeBasisPoints,
        uint256 _harvestTreasuryFeeBasisPoints,
        IERC4626 _prizeVault,
        address _treasury,
        bytes32 _salt,
        uint256 _initialDeposit,
        bool setupUniswapV4HookedPool
    ) public payable returns (FanToken fanToken) {
        address underlying = address(_prizeVault.asset());

        // TODO: use fancy cloning code
        fanToken = new FanToken{salt: _salt}(
            _name,
            _symbol,
            _harvestOwnerFeeBasisPoints,
            _harvestTreasuryFeeBasisPoints,
            msg.sender,
            _prizeVault,
            _treasury,
            WETH
        );

        _deployedTokens.add(address(fanToken));

        emit Created(msg.sender, address(_prizeVault), _treasury, address(fanToken));

        // TODO: set up the uniswap v4 pool for making trades transparently. Our mini-app should use our redeem/deposit helpers. but wallets already support getting prices through 0x/uniswap

        if (_initialDeposit > 0) {
            startDeposit(fanToken, _initialDeposit, msg.sender);
        }

        if (setupUniswapV4HookedPool) {
            _setupUniswapV4HookedPool(address(_prizeVault), underlying);
            _setupUniswapV4HookedPool(address(_prizeVault), address(fanToken));
        }
    }

    /// @notice Creates a Uniswap V4 pool if it doesn't already exist
    /// @dev This creates specialized pools for prize token ecosystems with custom hook logic
    /// @param tokenA First token address (either prize vault or fan token)
    /// @param tokenB Second token address (either underlying asset or prize vault)
    function _setupUniswapV4HookedPool(address tokenA, address tokenB) internal {
        /*
        POOL SETUP EXPLANATION:

        This creates Uniswap V4 pools with a custom hook that handles ERC4626 token mechanics.
        The hook overrides standard AMM pricing logic to provide seamless conversions between:
        1. Fan tokens ↔ Prize vault shares (handles deposit queue delays)
        2. Underlying assets ↔ Prize vault shares (direct conversions)

        Key design decisions:
        - Zero fees: These pools are for utility, not revenue
        - Custom hook: Handles async deposits/withdrawals and ERC4626 conversions
        - 1:1 initial price: Hook overrides pricing, so initial price is irrelevant

        TODO: async deposits are a problem for one of the trade directions.
        i think we can't use the existing hook for depositing into our fan tokens
        we can still use it for the underlyings though and one direction of the trades, so I think its worth setting up.
        this really makes me want to figure out a way to design this system without a delay queue on the deposits (and withdrawals).
        but i think we need the queue to be >2x longer than the prize draws/auctions.

        MAYBE there is a way to look at the underlying prize pool.
        */

        // Sort currencies (Uniswap V4 requires currency0 < currency1)
        (Currency currency0, Currency currency1) = tokenA < tokenB
            ? (Currency.wrap(tokenA), Currency.wrap(tokenB))
            : (Currency.wrap(tokenB), Currency.wrap(tokenA));

        // Create pool key for hooked pool with specialized ERC4626 handling
        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 0, // Zero fees - these pools provide utility, not revenue
            tickSpacing: 1, // Minimum tick spacing for zero fee pools
            hooks: UNISWAP_V4_HOOK // Custom hook handles all pricing and conversion logic
        });

        // Check if pool already exists by reading its slot0 state
        PoolId poolId = PoolId.wrap(keccak256(abi.encode(poolKey)));
        (uint160 sqrtPriceX96,,,) = StateLibrary.getSlot0(POOL_MANAGER, poolId);

        // Create pool if it doesn't exist (sqrtPriceX96 == 0 means uninitialized)
        if (sqrtPriceX96 == 0) {
            // Set initial price to 1:1 ratio - the hook will override all pricing logic anyway
            // The hook handles actual conversions based on ERC4626 exchange rates and deposit queues
            uint160 initialPrice = TickMath.getSqrtPriceAtTick(0); // Tick 0 = 1:1 price (2^96 in Q96 format)
            POOL_MANAGER.initialize(poolKey, initialPrice);
        }
    }

    function startDeposit(FanToken fanToken, uint256 underlyingAssets, address receiver)
        public
        payable
        returns (uint256)
    {
        // only allow depositing to a fan token that we deployed
        require(_deployedTokens.contains(address(fanToken)), InvalidFanToken());

        IERC4626 prizeVault = IERC4626(fanToken.asset());
        IERC20 underlying = IERC20(prizeVault.asset());

        if (msg.value > 0) {
            require(address(underlying) == address(WETH), IncorrectUnderlying(address(underlying)));

            // TODO: should we overwrite underlyingAssets (i think so), or should we require they match? less gas to do it this way
            underlyingAssets = msg.value;

            WETH.deposit{value: underlyingAssets}();
        } else {
            require(underlyingAssets > 0, NoUnderlyingAssets());

            // get the underlying into this contract so we can do things with it
            underlying.safeTransferFrom(msg.sender, address(this), underlyingAssets);
        }

        // deposit the underlying into the prize vault
        underlying.forceApprove(address(prizeVault), underlyingAssets);
        uint256 vaultShares = prizeVault.deposit(underlyingAssets, address(this));

        // deposit the prize vault shares for fan tokens
        // TODO: do infinite approval when the fan token is deployed instead?
        IERC20(address(prizeVault)).forceApprove(address(fanToken), vaultShares);

        // pass msg.sender so this can be added to the deposit queue for the correct user
        return fanToken._factoryStartDeposit(msg.sender, vaultShares, receiver);
    }

    function redeem(FanToken fanToken, uint256 shares, address receiver) public returns (uint256) {
        require(_deployedTokens.contains(address(fanToken)), InvalidFanToken());

        IERC4626 prizeVault = IERC4626(fanToken.asset());

        // get the fan tokens
        IERC20(address(fanToken)).safeTransferFrom(msg.sender, address(this), shares);

        // TODO: i think this transfer is broken. i think when it happens,

        // redeem the fan tokens
        uint256 vaultShares = fanToken.redeem(shares, address(this), address(this));

        // redeem the vault shares
        return prizeVault.redeem(vaultShares, receiver, address(this));
    }

    // TODO: do we need mint? mint is hard because we care about the assets, not the shares during the deposit queue.
    // TODO: do we need a withdraw? its similar to redeem but takes assets instead of shares

    function version() external pure returns (string memory) {
        return "3.0.0";
    }

    // === Enumeration Functions ===

    /// @notice get all deployed fan tokens (for off-chain use)
    /// @dev this can be expensive for large numbers of tokens, but should be fine for a long time on Base network
    function getAllDeployedTokens() external view returns (address[] memory) {
        return _deployedTokens.values();
    }

    /// @notice get a paginated list of deployed fan tokens
    /// @param start starting index (inclusive)
    /// @param end ending index (exclusive)
    function getDeployedTokens(uint256 start, uint256 end) external view returns (address[] memory) {
        return _deployedTokens.values(start, end);
    }

    /// @notice get the total number of deployed fan tokens
    function getDeployedTokenCount() external view returns (uint256) {
        return _deployedTokens.length();
    }

    /// @notice get a specific deployed fan token by index
    function getDeployedTokenAt(uint256 index) external view returns (address) {
        return _deployedTokens.at(index);
    }

    /// @notice check if a fan token was deployed by this factory
    function isDeployed(address token) external view returns (bool) {
        return _deployedTokens.contains(token);
    }
}
