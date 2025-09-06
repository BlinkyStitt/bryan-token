// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {AuctionSwapper} from "./forks/AuctionSwapper.sol";
import {ERC20, ERC4626, IERC20, IERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC4626EntryFees} from "./ERC4626EntryFees.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IWETH9} from "v4-periphery/src/interfaces/external/IWETH9.sol";

error InvalidAuctionToken();

/// @title FanToken.
/// @notice Play pool together as a group of fans.
contract FanToken is AuctionSwapper, ERC4626EntryFees, Ownable2Step {
    using Math for uint256;
    using SafeERC20 for IERC20;

    uint256 private constant _BASIS_POINT_SCALE = 1e4;

    /// @notice this amount of any harvested rewards that will be paid to the owner address. The rest inflate the values
    /// @dev 100 is 1%
    uint256 public harvestOwnerFeeBasisPoints;

    /// @notice this amount of any harvested rewards that will be paid to the treasury address
    /// @dev 100 is 1%
    uint256 public harvestTreasuryFeeBasisPoints;

    /// @notice the owner gets a portion of all deposits. A core design choice of this token is to make it easy to tip the owner.
    /// @dev 100 is 1%. Deposits send this percent to the owner.
    /// @dev I don't like how this doesn't match the pattern for the others. i want this to just be uint256 public entryFeeBasisPoints;
    uint256 private __entryFeeBasisPoints;

    /// @notice the treasury gets a configurable portion of all harvests
    address public treasury;

    /// @notice the backing token for this fan token
    IERC20 public immutable underlying;

    /// @notice make it easy to deposit by just sending ETH
    IWETH9 public immutable WETH;

    event NewTreasury(address indexed oldTreasury, address indexed newTreasury);

    /// @dev these underscores are gross. too many different libraries and styles are being mixed together
    /// todo: change this into an initializer that can only run once during deploy?
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 entryFeeBasisPoints,
        uint256 _harvestOwnerFeeBasisPoints,
        uint256 _harvestTreasuryFeeBasisPoints,
        address _owner,
        IERC4626 _prizeVault,
        address _treasury,
        IWETH9 _weth
    ) ERC20(_name, _symbol) ERC4626(_prizeVault) Ownable(_owner) {
        require(entryFeeBasisPoints <= _BASIS_POINT_SCALE);
        require(_harvestOwnerFeeBasisPoints + _harvestTreasuryFeeBasisPoints <= _BASIS_POINT_SCALE);

        underlying = IERC20(_prizeVault.asset());

        __entryFeeBasisPoints = entryFeeBasisPoints;

        // TODO: more general split contract?
        harvestOwnerFeeBasisPoints = _harvestOwnerFeeBasisPoints;
        harvestTreasuryFeeBasisPoints = _harvestTreasuryFeeBasisPoints;

        // default the treasury to the owner address. the owner can change this
        if (_treasury == address(0)) {
            require(harvestTreasuryFeeBasisPoints == 0);
        } else {
            treasury = _treasury;
        }

        // this isn't always needed, but might be useful
        WETH = _weth;

        setupApprovals();
    }

    /// @dev allow receiving eth
    receive() external payable {}

    // === Public buttons ===

    /// @notice reset this contract's approvals. You probably won't ever need to call this.
    function setupApprovals() public {
        underlying.forceApprove(asset(), type(uint256).max);
    }

    // === Owner only ===

    /// @dev if you want to lock the treasury address, you can `revokeOwnership()`
    function setTreasury(address newTreasury) public onlyOwner {
        emit NewTreasury(treasury, newTreasury);
        treasury = newTreasury;
    }

    // === Custom things ===

    /// @notice check an account's balance in the underlying (backing) token
    function underlyingBalanceOf(address who) public view returns (uint256) {
        uint256 fanTokenShares = balanceOf(who);

        // TODO: convertToAssets or previewRedeem? previewRedeem includes fees, so I think is a more useful balance to show.
        uint256 prizeVaultShares = previewRedeem(fanTokenShares);

        IERC4626 a = IERC4626(asset());

        return a.previewRedeem(prizeVaultShares);
    }

    // TODO: i feel like we should store a minimum trade amount here. but i don't know how to make that open. maybe this should be an only-owner function?
    function enableAuction(IERC20 from) public returns (bytes32) {
        IERC20 _asset = IERC20(asset());

        require(from != _asset, InvalidAuctionToken());
        require(from != underlying, InvalidAuctionToken());

        return _enableAuction(address(from), address(underlying));
    }

    /// @notice compound any underlying tokens. Fees may be sent to the owner or the treasury.
    function harvest() public returns (uint256 total) {
        // don't allow harvesting the backing token! that would be bad!
        IERC4626 prizeVault = IERC4626(asset());
        IERC20 underlyingToken = underlying;

        // if the underlying is WETH, wrap any ETH in this contract
        if (address(underlyingToken) == address(WETH) && address(this).balance > 0) {
            WETH.deposit{value: address(this).balance}();
        }

        // we want to use the entire balance
        total = underlyingToken.balanceOf(address(this));
        if (total == 0) {
            return total;
        }

        // get more tickets
        total = prizeVault.deposit(total, address(this));

        // optionally split some to a "treasury" address
        address treasuryAddress = treasury;
        if (treasuryAddress != address(0)) {
            // TODO: which way should we round?
            uint256 treasuryFee = total.mulDiv(harvestTreasuryFeeBasisPoints, _BASIS_POINT_SCALE, Math.Rounding.Ceil);
            if (treasuryFee > 0) {
                IERC20(address(prizeVault)).safeTransfer(treasuryAddress, treasuryFee);
            }
        }

        // optionally split some to an "owner" address
        address ownerAddress = owner();
        if (ownerAddress != address(0)) {
            // pay the owner part of the harvest
            // TODO: which way should we round?
            uint256 ownerFee = total.mulDiv(harvestOwnerFeeBasisPoints, _BASIS_POINT_SCALE, Math.Rounding.Ceil);
            if (ownerFee > 0) {
                IERC20(address(prizeVault)).safeTransfer(ownerAddress, ownerFee);
            }
        }

        // leave the remaining balance here. this will inflate the value of everyone's shares equally
    }

    // === Fee configuration ===

    function _entryFeeBasisPoints() internal view override returns (uint256) {
        return __entryFeeBasisPoints;
    }

    function _entryFeeRecipient() internal view override returns (address) {
        return owner();
    }
}
