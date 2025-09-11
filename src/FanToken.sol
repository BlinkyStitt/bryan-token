// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {Auction, AuctionSwapper} from "./forks/AuctionSwapper.sol";
import {ERC20, ERC4626, IERC20, IERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IWETH9} from "v4-periphery/src/interfaces/external/IWETH9.sol";
import {SponsorToken} from "./SponsorToken.sol";

import {console} from "forge-std/console.sol";

error InvalidAuctionToken();
error FeesTooLarge();
error FactoryOnly();
error Unimplemented(string err);

/// @title FanToken.
/// @notice Play pool together as a group of fans.
contract FanToken is AuctionSwapper, ERC4626, Ownable2Step {
    using Math for uint256;
    using SafeERC20 for IERC20;

    address public immutable FACTORY;

    /// @notice deposits are delayed to stop prizes from being taken unfairly
    /// @dev what should this be? i think it needs to be longer than two auctions with some buffer for bots to kick the auction
    uint256 public immutable DEPOSIT_DELAY = 3 days;

    uint256 private constant _BASIS_POINT_SCALE = 1e4;

    /// @notice this amount of any harvested rewards that will be paid to the owner address. The rest inflate the values
    /// @dev 100 is 1%
    uint256 public harvestOwnerFeeBasisPoints;

    /// @notice this amount of any harvested rewards that will be paid to the treasury address
    /// @dev 100 is 1%
    uint256 public harvestTreasuryFeeBasisPoints;

    /// @notice the treasury gets a configurable portion of all harvests
    /// todo: better name for this
    address public immutable treasury;

    /// @notice users can opt out of receiving rewards
    SponsorToken public immutable sponsorToken;

    /// @notice the backing token for this fan token's prize tickets. fan tokens can be redeemed for this token.
    /// @dev the linter says this should be capitalized
    IERC20 public immutable underlying;

    /// @notice if the underlying is WETH, make it easy to deposit by just sending ETH
    IWETH9 public immutable WETH;

    /// @notice assets held for the DEPOSIT_DELAY
    uint256 public totalPendingAssets = 0;

    struct PendingDeposit {
        uint256 when;
        uint256 assets;
    }

    /// TODO: include a nonce here so that multiple deposits don't reset the timer?
    mapping(address caller => mapping(address receiver => PendingDeposit)) public pendingDepositOf;

    /// @dev this is the number of assets, not the number of shares
    /// TODO: i'm not sure if tracking this is worth the gas
    mapping(address who => uint256) public balanceOfPending;

    /// @dev sponsor tokens do not earn any rewards
    mapping(address who => bool) public isSponsor;

    /// @dev this is the number of assets, not the number of shares
    mapping(address who => uint256) public balanceOfSponsor;

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
        require(_harvestOwnerFeeBasisPoints + _harvestTreasuryFeeBasisPoints <= _BASIS_POINT_SCALE, FeesTooLarge());
        require(_owner != address(0), "this looks like a mistake");

        FACTORY = msg.sender;

        underlying = IERC20(_prizeVault.asset());

        // TODO: i can't decide if this should have one
        harvestOwnerFeeBasisPoints = _harvestOwnerFeeBasisPoints;
        harvestTreasuryFeeBasisPoints = _harvestTreasuryFeeBasisPoints;

        // default the treasury to the owner address. the owner can change this
        if (_treasury == address(0)) {
            require(harvestTreasuryFeeBasisPoints == 0, FeesTooLarge());
        } else {
            treasury = _treasury;
        }

        // this isn't always needed, but might be useful
        WETH = _weth;

        setupApprovals();

        isSponsor[_owner] = true;

        if (_treasury != address(0)) {
            // TODO: this should maybe be optional
            isSponsor[_treasury] = true;
        }

        isSponsor[address(this)] = true;

        // TODO: i'm not sure about this. i think it just adds gas overhead. but it also seems like a good idea
        // TODO: maybe we should have a _transfer override that makes sure we aren't letting users call transfer to the factory
        isSponsor[msg.sender] = true;

        // TODO: is this an okay name
        string memory sponsorName = string(abi.encodePacked("Sponsored ", _name));
        string memory sponsorSymbol = string(abi.encodePacked("s", _symbol));

        sponsorToken = new SponsorToken(sponsorName, sponsorSymbol);
    }

    /// @dev allow receiving eth
    receive() external payable {}

    // === Initialization ===

    /// @notice reset this contract's approvals. You probably won't ever need to call this.
    function setupApprovals() public {
        underlying.forceApprove(asset(), type(uint256).max);
    }

    // === Internal ===

    /// @dev after the initial deposit, this does NOT transfer the tokens. instead, make sure `startDeposit` is called first
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        if (totalSupply() == 0) {
            // TODO: should this check `totalPendingAssets == 0`?
            // the first deposit shouldn't have any delay
            super._deposit(caller, receiver, assets, shares);
        } else {
            _finishDeposit(caller, receiver, assets, shares);
        }
    }

    /// @notice finish the deposit from any caller. The current caller does not need to be the same as the
    function _finishDeposit(address originalCaller, address receiver, uint256 assets, uint256 shares)
        internal
        returns (uint256)
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

        if (shares == 0) {
            shares = previewDeposit(assets);
        }

        pendingDeposit.when = 0;
        pendingDeposit.assets = 0;

        totalPendingAssets -= assets;

        balanceOfPending[receiver] -= assets;

        // TODO: different event if this is a sponsor
        emit Deposit(originalCaller, receiver, assets, shares);

        _mint(receiver, shares);

        return shares;
    }

    /**
     * @dev To override if a post take action is desired.
     *
     * This could be used to re-deploy the bought token back into the yield source,
     * or in conjunction with {_preTake} to check that the price sold at was within
     * some allowed range.
     *
     * @param _token Address of the token that the strategy was sent.
     * @param _amountTaken Amount of the from token taken.
     * @param _amountPayed Amount of `_token` that was sent to the strategy.
     */
    function _postTake(address _token, uint256 _amountTaken, uint256 _amountPayed) internal override {
        harvest();
    }

    /// @notice begin a deposit. This takes `assets()`, not `underlying()`
    /// @dev the first deposit does not have any delay
    /// @dev the delay is necessary to protect against large deposits around the time of a large win
    function _startDeposit(address caller, uint256 assets, address receiver) internal returns (uint256 when) {
        if (totalSupply() == 0) {
            uint256 shares = super.deposit(assets, receiver);
            when = 0;
        } else {
            PendingDeposit storage pendingDeposit = pendingDepositOf[caller][receiver];

            // this is from msg.sender, NOT caller. i don't love that.
            SafeERC20.safeTransferFrom(IERC20(asset()), msg.sender, address(this), assets);

            // update counters
            totalPendingAssets += assets;
            balanceOfPending[receiver] += assets;
            pendingDeposit.assets += assets;

            // allow claiming the deposit after a delay
            // if a deposit is already running, we reset the timestamp
            pendingDeposit.when = when = block.timestamp + DEPOSIT_DELAY;
        }
    }

    // === Public things ===

    /// @notice check an account's balance in the underlying (backing) token
    function balanceOfUnderlying(address who) public view returns (uint256) {
        uint256 fanTokenShares = balanceOf(who);

        // TODO: convertToAssets or previewRedeem?
        uint256 prizeVaultShares = previewRedeem(fanTokenShares);

        IERC4626 prizeVault = IERC4626(asset());

        // TODO: convertToAssets or previewRedeem? i'm pretty sure preview is correct
        return prizeVault.previewRedeem(prizeVaultShares);
    }

    /// @notice prepare the auction contract for selling a token
    /// TODO: i feel like we should store a minimum trade amount here. but i don't know how to make that open. maybe this should be an only-owner function?
    function enableAuction(IERC20 from) public returns (bytes32 auctionId) {
        IERC20 _asset = IERC20(asset());

        // don't allow auctioning the backing tokens! that would be bad!
        require(address(from) != address(this), InvalidAuctionToken());
        require(from != _asset, InvalidAuctionToken());
        require(from != underlying, InvalidAuctionToken());

        auctionId = _enableAuction(address(from), address(underlying));

        {
            // a simple balance check is enough
            bool _kickableSetting = false;
            // this transfers the tokens
            bool _kickSetting = true;
            // we don't use this
            bool _preTakeSetting = false;
            // this calls harvest for us when the auction is complete
            bool _postTakeSetting = true;

            Auction(auction).setHookFlags(_kickableSetting, _kickSetting, _preTakeSetting, _postTakeSetting);
        }

        // TODO: allow calling disable auction if none are pending? i think that just wastes gas

        // TODO: allow resetting this approval with a helper function
        from.forceApprove(auction, type(uint256).max);
    }

    /// @notice finish a deposit that was started by another caller
    function finishDeposit(address originalCaller, address receiver) public returns (uint256 shares) {
        shares = _finishDeposit(originalCaller, receiver, 0, 0);
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
                // TODO: send this to the SponsorToken and credit the treasury
                // TODO: send them fan tokens instead of prize vault
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
                // TODO: send this to the SponsorToken and credit the owner
                // TODO: send them fan tokens instead of prize vault
                IERC20(address(prizeVault)).safeTransfer(ownerAddress, ownerFee);
            }
        }

        // leave the remaining balance here. this will inflate the value of everyone's shares equally

        // correct the accounting for the sponsored tokens
        sponsorToken.burnExcess();
    }

    /// @notice begin a deposit. This takes `assets()`, not `underlying()`
    /// @dev the first deposit does not have any delay
    /// @dev the delay is necessary to protect against large deposits around the time of a large win
    function startDeposit(uint256 assets, address receiver) public returns (uint256 claimWhen) {
        return _startDeposit(msg.sender, assets, receiver);
    }

    /// @notice the factory is allowed to start deposits for a trusted `caller`
    function _factoryStartDeposit(address caller, uint256 assets, address receiver) public returns (uint256 claimWhen) {
        require(msg.sender == FACTORY, FactoryOnly());
        return _startDeposit(caller, assets, receiver);
    }

    /// @notice sponsored tokens contribute to prizes, but do not earn any prizes themselves.
    /// todo: what return value?
    /// TODO: time lock on this
    function sponsor(bool state) public {
        // todo: force keep it on for the owner/treasury?
        bool senderIsSponsor = isSponsor[msg.sender];

        uint256 shares = balanceOf(msg.sender);

        if (state) {
            // sponsorship should be on
            if (senderIsSponsor) {
                // sponsorship is already on. nothing to do
                return;                
            }
            isSponsor[msg.sender] = state;

            // transfer the tokens
            _update(msg.sender, address(sponsorToken), shares);

            // update accounting on the sponsor token side
            sponsorToken._internalMint(msg.sender, shares);
        } else {
            // sponsorship should be off
            if (!senderIsSponsor) {
                // sponsorship is already off. nothing to do
                return;
            }
            isSponsor[msg.sender] = state;

            sponsorToken._internalBurn(msg.sender, shares);
        }
    }

    // TODO: sponsorFrom? need an "operator" mapping i think

    // === minor helpers ===

    /// @notice wrap any ETH in this contract
    function wrapETH() public payable returns (uint256 total) {
        total = address(this).balance;
        if (total > 0) {
            WETH.deposit{value: total}();
        }
    }
}
