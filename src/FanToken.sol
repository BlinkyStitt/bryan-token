// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {AuctionSwapper} from "./forks/AuctionSwapper.sol";
import {ERC20, ERC4626, IERC20, IERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IWETH9} from "v4-periphery/src/interfaces/external/IWETH9.sol";
import {console} from "forge-std/console.sol";

error InvalidAuctionToken();

/// @title FanToken.
/// @notice Play pool together as a group of fans.
contract FanToken is AuctionSwapper, ERC4626, Ownable2Step {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /// @notice deposits are delayed to stop prizes from being taken unfairly
    /// @dev what should this be? i think it needs to be longer than the auction timer with some buffer for bots to kick the auction
    uint256 public immutable DEPOSIT_DELAY = 2 days;

    uint256 private constant _BASIS_POINT_SCALE = 1e4;

    /// @notice this amount of any harvested rewards that will be paid to the owner address. The rest inflate the values
    /// @dev 100 is 1%
    uint256 public harvestOwnerFeeBasisPoints;

    /// @notice this amount of any harvested rewards that will be paid to the treasury address
    /// @dev 100 is 1%
    uint256 public harvestTreasuryFeeBasisPoints;

    /// @notice the treasury gets a configurable portion of all harvests
    address public immutable treasury;

    /// @notice the backing token for this fan token
    /// @dev the linter says this should be capitalized
    IERC20 public immutable underlying;

    /// @notice if the underlying ismake it easy to deposit by just sending ETH
    IWETH9 public immutable WETH;

    /// @notice assets held for the DEPOSIT_DELAY
    uint256 public totalPendingDeposits = 0;

    /// TODO: think more about this. if the asset suffers a loss, I think some trickery can happen here. ironic since we added this to help when we have a large win
    struct PendingDeposit {
        uint256 when;
        uint256 assets;
    }

    /// TODO: include a nonce here so that multiple deposits don't reset the timer?
    mapping(address caller => mapping(address receiver => PendingDeposit)) public pendingDepositOf;

    mapping(address owner => uint256) public pendingBalanceOf;

    /// @dev these underscores are gross. too many different libraries and styles are being mixed together
    /// todo: change this into an initializer that can only run once during deploy?
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _harvestOwnerFeeBasisPoints,
        uint256 _harvestTreasuryFeeBasisPoints,
        address _owner,
        IERC4626 _prizeVault,
        address _treasury,
        IWETH9 _weth
    ) ERC20(_name, _symbol) ERC4626(_prizeVault) Ownable(_owner) {
        require(_harvestOwnerFeeBasisPoints + _harvestTreasuryFeeBasisPoints <= _BASIS_POINT_SCALE);

        underlying = IERC20(_prizeVault.asset());

        // TODO: i can't decide if this should have one
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

    // === Initialization ===

    /// @notice reset this contract's approvals. You probably won't ever need to call this.
    function setupApprovals() public {
        underlying.forceApprove(asset(), type(uint256).max);
    }

    // === Internal ===

    /// @dev this does NOT call the super.deposit. The tokens must already be pending deposit
    /// @dev this does NOT transfer the tokens. instead we make sure a `startDeposit` was already called
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        if (totalSupply() == 0) {
            // the first deposit shouldn't have any delay
            super._deposit(caller, receiver, assets, shares);
        } else {
            // TODO: i think this has bugs
            uint256 finishedShares = _finishDeposit(caller, receiver, assets);

            require(finishedShares == shares, "!shares");
        }
    }

    /// @notice finish the deposit from any caller. The current caller does not need to be the same as the
    function _finishDeposit(address originalCaller, address receiver, uint256 assets)
        internal
        returns (uint256 shares)
    {
        PendingDeposit storage pendingDeposit = pendingDepositOf[originalCaller][receiver];

        // TODO: custom error
        require(pendingDeposit.when != 0 && block.timestamp >= pendingDeposit.when, "!now");

        if (assets == 0) {
            assets = pendingDeposit.assets;
        } else {
            // TODO: custom error
            require(pendingDeposit.assets == assets, "!assets");
        }

        pendingDeposit.assets = 0;
        pendingDeposit.when = 0;

        totalPendingDeposits -= assets;

        pendingBalanceOf[receiver] -= assets;

        // TODO: this should maybe be a function argument
        shares = previewDeposit(assets);

        _mint(receiver, shares);

        emit Deposit(originalCaller, receiver, assets, shares);
    }

    // === Public things ===

    /// @notice check an account's balance in the underlying (backing) token
    function balanceOfUnderlying(address who) public view returns (uint256) {
        uint256 fanTokenShares = balanceOf(who);

        // TODO: convertToAssets or previewRedeem?
        uint256 prizeVaultShares = previewRedeem(fanTokenShares);

        IERC4626 prizeVault = IERC4626(asset());

        // TODO: convertToAssets or previewRedeem?
        return prizeVault.previewRedeem(prizeVaultShares);
    }

    // TODO: i feel like we should store a minimum trade amount here. but i don't know how to make that open. maybe this should be an only-owner function?
    function enableAuction(IERC20 from) public returns (bytes32) {
        IERC20 _asset = IERC20(asset());

        // don't allow auctioning the backing tokens! that would be bad!
        require(address(from) != address(this), InvalidAuctionToken());
        require(from != _asset, InvalidAuctionToken());
        require(from != underlying, InvalidAuctionToken());

        return _enableAuction(address(from), address(underlying));
    }

    function finishDeposit(address originalCaller, address receiver) public returns (uint256) {
        return _finishDeposit(originalCaller, receiver, 0);
    }

    /// @notice compound any underlying tokens. Fees may be sent to the owner or the treasury.
    function harvest() public payable returns (uint256 total) {
        IERC4626 prizeVault = IERC4626(asset());
        IERC20 underlyingToken = underlying;

        if (address(underlying) == address(WETH)) {
            wrapETH();
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
            uint256 treasuryFee = total.mulDiv(harvestTreasuryFeeBasisPoints, _BASIS_POINT_SCALE, Math.Rounding.Floor);
            if (treasuryFee > 0) {
                IERC20(address(prizeVault)).safeTransfer(treasuryAddress, treasuryFee);
            }
        }

        // optionally split some to an "owner" address
        address ownerAddress = owner();
        if (ownerAddress != address(0)) {
            // pay the owner part of the harvest
            // TODO: which way should we round?
            uint256 ownerFee = total.mulDiv(harvestOwnerFeeBasisPoints, _BASIS_POINT_SCALE, Math.Rounding.Floor);
            if (ownerFee > 0) {
                IERC20(address(prizeVault)).safeTransfer(ownerAddress, ownerFee);
            }
        }

        // leave the remaining balance here. this will inflate the value of everyone's shares equally
    }

    /// @notice begin a deposit
    /// @dev the first deposit shouldn't have any delay
    /// @dev this is necessary to protect against large deposits around the time of a large win
    function startDeposit(uint256 assets, address receiver) public returns (uint256 shares) {
        if (totalSupply() == 0) {
            shares = super.deposit(assets, receiver);
        } else {
            PendingDeposit storage pendingDeposit = pendingDepositOf[msg.sender][receiver];

            // if a deposit is already running, then we don't allow starting a new one
            // TODO: if receiver is the message.sender, maybe we should allow extending the when indefinitely?
            require(pendingDeposit.when == 0, "!now");

            shares = previewDeposit(assets);
            SafeERC20.safeTransferFrom(IERC20(asset()), msg.sender, address(this), assets);

            totalPendingDeposits += assets;

            pendingBalanceOf[receiver] += assets;

            pendingDeposit.assets += assets;
            pendingDeposit.when = block.timestamp + DEPOSIT_DELAY;
        }
    }

    /// @dev this does not include the pending deposits
    function totalAssets() public view override returns (uint256) {
        return super.totalAssets() - totalPendingDeposits;
    }

    /// @notice wrap any ETH in this contract
    function wrapETH() public payable returns (uint256 total) {
        uint256 thisBalance = address(this).balance;
        if (thisBalance > 0) {
            WETH.deposit{value: thisBalance}();
        }
    }
}
