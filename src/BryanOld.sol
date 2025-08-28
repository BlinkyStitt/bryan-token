// SPDX-License-Identifier: AGPL-3.0-only
// This is an experiment in a "social token". It is an ERC-20 with some extra pieces.
// TODO: permit for allowances? the name can change and that complicates things. <https://docs.openzeppelin.com/contracts/5.x/api/token/erc20#ERC20Permit>
// TODO: i think this should be a 4626 contract
// TODO: solady or oz?
pragma solidity ^0.8.13;

import {ERC20} from "@solady/tokens/ERC20.sol";
import {PrizeVault} from "./interfaces/PrizeVault.sol";
import {PrizePool} from "./interfaces/PrizePool.sol";
import {PrizePoolTwabRewards} from "./interfaces/PrizePoolTwabRewards.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";

error Unauthorized();
error LowBalance();

contract BryanOld {
    /// @dev Immutable variables cannot have a non-value type.
    string public name = "Bryan 3";

    /// @dev Immutable variables cannot have a non-value type.
    string public symbol = "BRY3";

    uint8 public immutable decimals;

    ERC20 public immutable asset;
    PrizePoolTwabRewards public immutable prizePoolTwabRewards;
    PrizeVault public immutable prizeVault;

    /// @notice the current owner of the contract. has power to mint and burn
    /// @dev With a smart-contract as the owner, more advancted authentication can be added.
    address public owner;

    /// @notice the next owner of the contract. will have the power to mint and burn after claiming ownership
    address public nextOwner;

    /// @notice the receipient of any prizes
    address public treasury;

    /// @notice the total supply of this erc20 token
    /// @dev Do not manually set balances without updating totalSupply, as the sum of all user balances must not exceed it.
    uint256 public totalSupply;

    /// @notice the balances of this erc20 token
    mapping(address => uint256) public balanceOf;

    /// @notice the allowances of this erc20 token
    mapping(address => mapping(address => uint256)) public allowance;

    event Approval(address indexed _owner, address indexed _spender, uint256 _value);
    event Transfer(address indexed _from, address indexed _to, uint256 _value);

    event NextOwner(address indexed _from, address indexed _to);
    event ClaimOwnership(address indexed _from, address indexed _to);

    constructor(address _owner, address _prizePoolTwabRewards, address _prizeVault) {
        owner = _owner;
        emit ClaimOwnership(address(0), _owner);

        // TODO: can we get to this address from the vault?
        prizePoolTwabRewards = PrizePoolTwabRewards(_prizePoolTwabRewards);

        prizeVault = PrizeVault(_prizeVault);

        asset = ERC20(prizeVault.asset());

        decimals = prizeVault.decimals();

        treasury = _owner;

        internalApprovals();
    }

    function internalApprovals() public {
        asset.approve(address(prizeVault), type(uint256).max);
    }

    //
    // modifiers
    //
    modifier ownerOnly() {
        require(msg.sender == owner, Unauthorized());
        _;
    }

    //
    // owner-only setters
    //
    function setNextOwner(address newOwner) public ownerOnly returns (bool success) {
        nextOwner = newOwner;
        emit NextOwner(msg.sender, newOwner);
        return true;
    }

    function claimOwnership() public returns (bool success) {
        require(msg.sender == nextOwner);

        emit ClaimOwnership(owner, nextOwner);

        owner = nextOwner;
        nextOwner = address(1);

        return true;
    }

    function setTreasury(address newTreasury) public ownerOnly returns (bool success) {}

    //
    // internal
    //
    function _deposit(address to, uint256 amount) internal returns (uint256 shares) {
        SafeTransferLib.safeTransferFrom(address(asset), to, address(this), amount);

        shares = prizeVault.deposit(amount, address(this));

        totalSupply += shares;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += shares;
        }

        emit Transfer(address(0), to, shares);
    }

    function _redeem(address from, uint256 shares, uint256 minAssets) internal returns (uint256 assets) {
        assets = prizeVault.redeem(shares, from, address(this), minAssets);

        balanceOf[from] -= shares;

        // Cannot underflow because a user's balance
        // will never be larger than the total supply.
        unchecked {
            totalSupply -= shares;
        }

        emit Transfer(from, address(0), shares);
    }

    // TODO: need _withdraw probably too

    //
    // standard erc20 things
    //
    function approve(address spender, uint256 amount) public returns (bool) {
        allowance[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);

        return true;
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        balanceOf[msg.sender] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(msg.sender, to, amount);

        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.

        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;

        balanceOf[from] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);

        return true;
    }

    //
    // non-standard token things
    //
    function deposit(uint256 assets) public returns (uint256 shares) {
        shares = _deposit(msg.sender, assets);
    }

    /// @dev send BRY3 to receive USDC
    function redeem(uint256 shares, uint256 minAssets) public returns (uint256 assets) {
        assets = _redeem(msg.sender, shares, minAssets);
    }

    //
    // Prize things
    //
    function claimRewards(uint256 _promotionId, uint8[] calldata _epochIds) public returns (uint256 rewards) {
        // TODO: is this address(this) correct? can we put the treasury address there?
        rewards = prizePoolTwabRewards.claimRewards(address(prizeVault), address(this), _promotionId, _epochIds);

        PrizePoolTwabRewards.Promotion memory promotion = prizePoolTwabRewards.getPromotion(_promotionId);

        SafeTransferLib.safeTransfer(address(promotion.token), treasury, rewards);
    }

    function sweepPrize() public returns (uint256 amount) {
        ERC20 prizeToken = ERC20(PrizePool(prizeVault.prizePool()).prizeToken());

        amount = prizeToken.balanceOf(address(this));

        SafeTransferLib.safeTransfer(address(prizeToken), treasury, amount);
    }

    function delegatePrize() public ownerOnly returns (bool) {
        // TODO: delegate prizes to the treasury address. this means we won't have to sweep anything from here
        revert("wip");
        return true;
    }
}
