// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

// TODO: use cloneable instead of deploying a full contract every time?

import {FanToken, SafeERC20, IERC20, IERC4626, IWETH9} from "./FanToken.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

error InvalidFanToken();
error IncorrectUnderlying(address underlying);
error NoUnderlyingAssets();

contract FanTokenFactory {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice make it easy to deposit by just sending ETH
    IWETH9 public immutable WETH;

    /// @notice enumerable set of all deployed fan tokens
    EnumerableSet.AddressSet private _deployedTokens;

    // TODO: how should we do indexes on this?
    event Created(address indexed _owner, address indexed _prizeVault, address indexed _treasury, address _token);

    constructor(IWETH9 _weth) {
        WETH = _weth;
    }

    function create(
        string memory _name,
        string memory _symbol,
        uint256 _harvestOwnerFeeBasisPoints,
        uint256 _harvestTreasuryFeeBasisPoints,
        IERC4626 _prizeVault,
        address _treasury,
        bytes32 _salt,
        uint256 _initialDeposit
    ) public payable returns (FanToken fanToken) {
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

    // TODO: do we need mint/withdraw?

    function version() external pure returns (string memory) {
        return "3.0.0";
    }

    // === Enumeration Functions ===

    /// @notice get all deployed fan tokens (for off-chain use)
    /// @dev this can be expensive for large numbers of tokens, but fine for Base network
    function getAllDeployedTokens() external view returns (address[] memory) {
        return _deployedTokens.values();
    }

    /// @notice get a paginated list of deployed fan tokens
    /// @param start starting index (inclusive)
    /// @param end ending index (exclusive)
    /// @dev uses OpenZeppelin's efficient pagination: values(set, start, end)
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
