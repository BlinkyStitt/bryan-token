// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

// TODO: use cloneable instead of deploying a full contract every time?

import {FanToken, SafeERC20, IERC20, IERC4626, IWETH9} from "./FanToken.sol";

error InvalidFanToken();
error IncorrectUnderlying(address underlying);

contract FanTokenFactory {
    using SafeERC20 for IERC20;

    /// @notice make it easy to deposit by just sending ETH
    IWETH9 public immutable WETH;

    mapping(address => bool) public deployed;

    // TODO: how should we do indexes on this?
    event Created(address indexed _owner, address indexed _prizeVault, address indexed _treasury, address _token);

    constructor(IWETH9 _weth) {
        WETH = _weth;
    }

    function create(
        string memory _name,
        string memory _symbol,
        uint256 _depositDelay,
        uint256 _harvestOwnerFeeBasisPoints,
        uint256 _harvestTreasuryFeeBasisPoints,
        IERC4626 _prizeVault,
        address _treasury,
        bytes32 _salt,
        uint256 _initialDeposit
    ) public payable returns (FanToken fanToken) {
        // TODO: what minimum/maximum deposit delay should we enfoce?
        require(_depositDelay >= 1 days);
        require(_depositDelay <= 2 weeks);

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

        // TODO: use a bitmap here?
        deployed[address(fanToken)] = true;

        emit Created(msg.sender, address(_prizeVault), _treasury, address(fanToken));

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
        require(deployed[address(fanToken)] == true, InvalidFanToken());

        IERC4626 prizeVault = IERC4626(fanToken.asset());
        IERC20 underlying = IERC20(prizeVault.asset());

        if (msg.value > 0) {
            require(address(underlying) == address(WETH), IncorrectUnderlying(address(underlying)));

            // TODO: should we overwrite underlyingAssets (i think so), or should we require they match? less gas to do it this way
            underlyingAssets = msg.value;

            WETH.deposit{value: underlyingAssets}();
        } else {
            // TODO: custom error instead of string errors
            require(underlyingAssets > 0, "no underlying assets");

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
        return fanToken.startDepositFor(msg.sender, vaultShares, receiver);
    }

    function redeem(FanToken fanToken, uint256 shares, address receiver) public returns (uint256) {
        require(deployed[address(fanToken)] == true, InvalidFanToken());

        IERC4626 prizeVault = IERC4626(fanToken.asset());

        // get the fan tokens
        IERC20(address(fanToken)).safeTransferFrom(msg.sender, address(this), shares);

        // redeem the fan tokens
        uint256 vaultShares = fanToken.redeem(shares, address(this), address(this));

        // redeem the vault shares
        return prizeVault.redeem(vaultShares, receiver, address(this));
    }

    // TODO: do we need mint/withdraw?
}
