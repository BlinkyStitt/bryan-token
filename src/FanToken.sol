// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {Auction, AuctionSwapper} from "./forks/AuctionSwapper.sol";
import {ERC20, ERC4626, IERC20, IERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IWETH9} from "v4-periphery/src/interfaces/external/IWETH9.sol";

import {console} from "forge-std/console.sol";

error InvalidAuctionToken();
error FeesTooLarge();
error FactoryOnly();
error Unimplemented(string err);

interface IFanTokenFactory {
    function version() external returns (string memory);
}

/// @title FanToken.
/// @notice Play pool together as a group of fans.
contract FanToken is AuctionSwapper, ERC4626, Ownable2Step {
    using Math for uint256;
    using SafeERC20 for IERC20;

    IFanTokenFactory public immutable FACTORY;

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

    /// @notice the backing token for this fan token's prize tickets. fan tokens can be redeemed for this token.
    /// @dev the linter says this should be capitalized
    IERC20 public immutable underlying;

    /// @notice if the underlying is WETH, make it easy to deposit by just sending ETH
    IWETH9 public immutable WETH;

    /// @notice assets held for the DEPOSIT_DELAY
    uint256 public totalPendingAssets = 0;

    uint256 public totalSponsorAssets = 0;

    struct PendingDeposit {
        uint256 when;
        uint256 assets;
        uint256 sharesAtStart;
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

        FACTORY = IFanTokenFactory(msg.sender);

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

        // TODO: think more about this. fan tokens here are special
        // isSponsor[address(this)] = true;

        // TODO: i'm not sure about this. i think it just adds gas overhead. but it also seems like a good idea
        // TODO: maybe we should have a _transfer override that makes sure we aren't letting users call transfer to the factory
        isSponsor[msg.sender] = true;
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
            shares = previewWithdraw(assets);
        }

        if (shares < pendingDeposit.sharesAtStart) {
            // we have extra shares. this is interest that was earned while the tokens were in the deposit queue. we need to burn them
            _update(address(this), address(0), pendingDeposit.sharesAtStart - shares);

            // note: if the share value went down, we don't do mint extra. we want everyone to lose equally if there are any loses
        }

        pendingDeposit.when = 0;
        pendingDeposit.assets = 0;
        pendingDeposit.sharesAtStart = 0;

        totalPendingAssets -= assets;

        balanceOfPending[receiver] -= assets;

        _update(address(this), receiver, shares);

        _setSponsorship(receiver, isSponsor[receiver]);

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

            // calculate share value BEFORE doing the transfer
            uint256 shares = previewDeposit(assets);

            // this is from msg.sender, NOT caller. i don't love that.
            SafeERC20.safeTransferFrom(IERC20(asset()), msg.sender, address(this), assets);

            _mint(address(this), shares);

            // update counters
            totalPendingAssets += assets;
            balanceOfPending[receiver] += assets;
            pendingDeposit.assets += assets;
            pendingDeposit.sharesAtStart += shares;

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

            // TODO: there is a new auction contract. i think they got rid of hooks
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
    /// @dev you probably want to kick an auction of POOL and maybe other tokens before calling this
    function harvest() public payable returns (uint256 underlyingAssets) {
        IERC4626 prizeVault = IERC4626(asset());
        IERC20 underlyingToken = underlying;

        if (address(underlying) == address(WETH)) {
            wrapETH();
        }

        // we want to use the entire balance
        underlyingAssets = underlyingToken.balanceOf(address(this));
        if (underlyingAssets == 0) {
            return underlyingAssets;
        }

        // calculate how many more tickets we can get
        // TODO: check maxDeposit? this might just be a waste of gas, but i think its a good idea
        uint256 maxDeposit = prizeVault.maxDeposit(address(this));

        // TODO: does OZ have a Math helper for this?
        if (underlyingAssets > maxDeposit) {
            // TODO: what should we do with any excess? hopefully it can be deposited in the future?
            underlyingAssets = maxDeposit;
        }

        // assets = prizeVault.deposit(total, address(this));
        uint256 assets = prizeVault.previewDeposit(underlyingAssets);

        // TODO: calculate treasury fee
        // we aren't going to actually make this many shares. but we might depending on the treasury/owner sponsorship settings
        uint256 shareValue = previewDeposit(assets);

        prizeVault.deposit(underlyingAssets, address(this));

        // optionally split some to a "treasury" address
        address treasuryAddress = treasury;
        if (treasuryAddress != address(0)) {
            // TODO: which way should we round? floor seems like a safe default
            uint256 treasuryFeeShares =
                shareValue.mulDiv(harvestTreasuryFeeBasisPoints, _BASIS_POINT_SCALE, Math.Rounding.Floor);
            if (treasuryFeeShares > 0) {
                // TODO: MORE TO DO HERE! WE NEED _mint (actually _update) to check if things are sponsors
                // TODO: theres a few options here. we can give them fan tokens or assets or underlying. fan tokens (with sponsorship) seems best
                _mint(treasuryAddress, treasuryFeeShares);
            }
        }

        // optionally split some to an "owner" address
        // TODO: DRY. this is the same as the treasury code above
        address ownerAddress = owner();
        if (ownerAddress != address(0)) {
            uint256 ownerFeeShares =
                shareValue.mulDiv(harvestOwnerFeeBasisPoints, _BASIS_POINT_SCALE, Math.Rounding.Floor);
            if (ownerFeeShares > 0) {
                _mint(ownerAddress, ownerFeeShares);
            }
        }

        // leave the remaining balance here. this will inflate the value of everyone's shares equally

        // correct the accounting for the sponsored tokens
        harvestSponsorship();
    }

    /// @notice send any rewards on sponsored tokens to the other token holders
    /// @dev this gets called as part of the main `harvest` function.
    function harvestSponsorship() public returns (uint256 amount) {
        uint256 correctShares = previewWithdraw(totalSponsorAssets);

        uint256 currentShares = balanceOf(address(this));

        if (currentShares > correctShares) {
            amount = currentShares - correctShares;
            _burn(address(this), amount);
        }
    }

    /**
     * @dev See {IERC4626-redeem}.
     */
    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256) {
        if (isSponsor[owner]) {
            uint256 ownerSponsorShares = previewWithdraw(balanceOfSponsor[owner]);

            if (shares > ownerSponsorShares) {
                revert ERC20InsufficientBalance(owner, ownerSponsorShares, shares);
            }

            super._update(address(this), owner, shares);
        }
        return super.redeem(shares, receiver, owner);
    }

    /// @notice begin a deposit. This takes `assets()`, not `underlying()`.
    function startDeposit(uint256 assets) public returns (uint256 claimWhen) {
        return _startDeposit(msg.sender, assets, msg.sender);
    }

    /// @notice begin a deposit for a different account. This takes `assets()`, not `underlying()`
    /// @dev the first deposit does not have any delay
    /// @dev the delay is necessary to protect against large deposits around the time of a large win
    function startDeposit(uint256 assets, address receiver) public returns (uint256 claimWhen) {
        return _startDeposit(msg.sender, assets, receiver);
    }

    /// @notice the factory is allowed to start deposits for a trusted `caller`
    function _factoryStartDeposit(address caller, uint256 assets, address receiver)
        public
        returns (uint256 claimWhen)
    {
        require(msg.sender == address(FACTORY), FactoryOnly());
        return _startDeposit(caller, assets, receiver);
    }

    /// @notice sponsored tokens contribute to prizes, but do not earn any prizes themselves.
    /// todo: what return value?
    /// TODO: time lock on this? i think its kind of pointless since people could just make a new address and send
    /// TODO: override _update to handle transfers on sponsored addresses? maybe first we should make a transferSponsored function just to get it working. then figure out how to merge them so that normal transfers will work?
    /// TODO: maybe a separate contract is better. then things like `balanceOf` won't be against the spec
    function setSponsorship(bool state) public {
        harvestSponsorship();

        _setSponsorship(msg.sender, state);
    }

    function _update(address from, address to, uint256 amount) internal override {
        super._update(from, to, amount);

        // this might be too gas heavy. but i think it ensures we always have the right accounting.
        _setSponsorship(from, isSponsor[from]);
        _setSponsorship(to, isSponsor[to]);
    }

    /// TODO: this needs more tests and coverage!
    function _setSponsorship(address who, bool state) internal {
        // todo? require msg.sender != owner() && msg.sender != treasury?
        bool senderIsSponsor = isSponsor[who];

        if (state) {
            // sponsorship should be on
            if (!senderIsSponsor) {
                isSponsor[who] = state;
            }

            // transfer all of the sender's fan tokens to this address
            uint256 shares = balanceOf(who);
            if (shares > 0) {
                _update(who, address(this), shares);

                // update sponsor accounting
                uint256 assets = previewRedeem(shares);
                totalSponsorAssets += assets;
                balanceOfSponsor[who] += assets;
                // TODO: emit events
            }
        } else {
            // sponsorship should be off
            if (senderIsSponsor) {
                isSponsor[who] = state;
            }

            // transfer the fan tokens back to the caller
            uint256 assets = balanceOfSponsor[who];
            if (assets > 0) {
                uint256 shares = previewWithdraw(assets);

                // update sponsor accounting
                balanceOfSponsor[who] -= assets;
                totalSponsorAssets -= assets;

                _update(address(this), who, shares);
            }
        }
    }

    /// @notice burn your sponsored tokens and credit them to all the other fan token holders
    function sponsorBurn(uint256 assets) public {
        uint256 senderSponsorAssets = balanceOfSponsor[msg.sender];
        if (assets > senderSponsorAssets) {
            revert ERC20InsufficientBalance(msg.sender, senderSponsorAssets, assets);
        }

        balanceOfSponsor[msg.sender] -= assets;
        totalSponsorAssets -= assets;

        harvestSponsorship();
    }

    /// @dev i keep trying to include this logic inside _update, but it breaks things
    function _sponsorTransfer(address from, address to, uint256 assets) internal {
        bool fromIsSponsor = isSponsor[from];
        bool toIsSponsor = isSponsor[to];

        uint256 shares = previewWithdraw(assets);

        // this isn't the most gas efficient way, but i think its best to ensure we get all the math right
        if (fromIsSponsor && toIsSponsor) {
            // no need to do anything with the shares. they are owned by this contract and stay owned by this contract
            balanceOfSponsor[from] -= assets;
            balanceOfSponsor[to] += assets;
            emit Transfer(from, to, shares);
        } else if (fromIsSponsor) {
            // since from is a sponsor, the shares are held by this contract
            // move them to the from. then do the normal transfer flow
            // we could maybe _update(address(this, to)), but i think events are confusing that way
            _update(address(this), from, shares);

            _update(from, to, shares);

            // update sponsorship accounting. this is probably overkill, but i think its safest
            _setSponsorship(from, true);
        } else if (toIsSponsor) {
            // from already holds shares.
            _update(from, to, shares);

            // this will move the shares to this contract and update sponsorhip accounting
            _setSponsorship(to, true);
        } else {
            revert Unimplemented("at least one side must be a sponsor");
        }
    }

    /// @dev i wanted to override `transfer` to work transparently, but that got too complicated quickly
    function sponsorTransfer(address to, uint256 assets) public returns (bool) {
        _sponsorTransfer(msg.sender, to, assets);
        return true;
    }

    /// @dev i wanted to override `transfer` to work transparently, but that got too complicated quickly
    function sponsorTransferFrom(address from, address to, uint256 assets) public returns (bool) {
        revert("todo: check approvals");
        _sponsorTransfer(from, to, assets);
        return true;
    }

    // TODO: sponsorTransferFrom

    // TODO: sponsorFrom? need an "operator" mapping i think

    /**
     * @dev See {IERC4626-withdraw}.
     */
    function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256) {
        if (isSponsor[owner]) {
            uint256 ownerSponsorShares = previewWithdraw(balanceOfSponsor[owner]);
            uint256 shares = previewWithdraw(assets);

            if (shares > ownerSponsorShares) {
                revert ERC20InsufficientBalance(owner, ownerSponsorShares, shares);
            }

            super._update(address(this), owner, shares);
        }
        return super.withdraw(assets, receiver, owner);
    }

    /// TODO: this isn't really necessary
    function totalSponsoredShares() public returns (uint256 shares) {
        shares = balanceOf(address(this));
    }

    /// TODO: this isn't really necessary
    function totalSponsoredAssets() public returns (uint256 assets) {
        uint256 shares = totalSponsoredShares();
        assets = previewRedeem(shares);
    }

    // === minor helpers ===

    function version() public returns (string memory) {
        return FACTORY.version();
    }

    /// @notice wrap any ETH in this contract
    function wrapETH() public payable returns (uint256 total) {
        total = address(this).balance;
        if (total > 0) {
            WETH.deposit{value: total}();
        }
    }
}
