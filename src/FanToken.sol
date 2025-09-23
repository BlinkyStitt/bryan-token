// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {IAuctionFactory} from "tokenized-strategy-periphery/src/interfaces/IAuctionFactory.sol";
import {AuctionSwapper, IAuction} from "./forks/AuctionSwapper.sol";
import {ERC20, ERC4626, IERC20, IERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IWETH9} from "v4-periphery/src/interfaces/external/IWETH9.sol";

error InvalidAuctionToken();
error FeesTooLarge();
error FactoryOnly();
error Unimplemented(string err);
error ZeroOwner();
error DepositNotReady();
error IncorrectAssets();
error AtLeastOneSideMustBeSponsor();
error InsufficientSponsorBalance(
    address owner, uint256 availableAssets, uint256 availableShares, uint256 requestedAssets, uint256 requestedShares
);

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
    address public immutable TREASURY;

    /// @notice the backing token for this fan token's prize tickets. fan tokens can be redeemed for this token.
    /// @dev the linter says this should be capitalized
    IERC20 public immutable UNDERLYING;

    /// @notice if the underlying is WETH, make it easy to deposit by just sending ETH
    IWETH9 public immutable WETH;

    IAuctionFactory public constant AUCTION_FACTORY = IAuctionFactory(0xbC587a495420aBB71Bbd40A0e291B64e80117526);

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

    /// @dev this is the number of assets, not the number of shares - stores asset amounts for sponsor accounting
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
        require(_owner != address(0), ZeroOwner());

        FACTORY = IFanTokenFactory(msg.sender);

        UNDERLYING = IERC20(_prizeVault.asset());

        // TODO: i can't decide if this should have one
        harvestOwnerFeeBasisPoints = _harvestOwnerFeeBasisPoints;
        harvestTreasuryFeeBasisPoints = _harvestTreasuryFeeBasisPoints;

        // default the treasury to the owner address. the owner can change this
        if (_treasury == address(0)) {
            require(harvestTreasuryFeeBasisPoints == 0, FeesTooLarge());
        } else {
            TREASURY = _treasury;
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

        IAuction auction = IAuction(AUCTION_FACTORY.createNewAuction(address(UNDERLYING)));
        _setAuction(address(auction));
    }

    /// @dev allow receiving eth
    receive() external payable {}

    // === Initialization ===

    /// @notice reset this contract's approvals. You probably won't ever need to call this.
    function setupApprovals() public {
        UNDERLYING.forceApprove(asset(), type(uint256).max);
    }

    // === Internal ===

    /// @dev after the initial deposit, this does NOT transfer the tokens. instead, make sure `startDeposit` is called first
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        if (totalSupply() == 0) {
            // totalPendingAssets will always be 0 here because pending deposits can only exist
            // when totalSupply() > 0 (startDeposit requires existing shares for price calculation)
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

        require(pendingDeposit.when != 0 && block.timestamp >= pendingDeposit.when, DepositNotReady());

        if (assets == 0) {
            assets = pendingDeposit.assets;
        } else {
            require(pendingDeposit.assets == assets, IncorrectAssets());
        }

        if (shares == 0) {
            // Calculate shares at finalization time using current share price
            shares = previewDeposit(assets);
        }

        // Mint the shares now that we're finalizing the deposit
        _mint(address(this), shares);

        pendingDeposit.when = 0;
        pendingDeposit.assets = 0;
        pendingDeposit.sharesAtStart = 0;

        totalPendingAssets -= assets;

        balanceOfPending[receiver] -= assets;

        _update(address(this), receiver, shares);

        _setSponsorship(receiver, isSponsor[receiver]);

        return shares;
    }

    /// @notice begin a deposit. This takes `assets()`, not `underlying()`
    /// @dev the first deposit does not have any delay
    /// @dev the delay is necessary to protect against large deposits around the time of a large win
    function _startDeposit(address caller, uint256 assets, address receiver) internal returns (uint256 when) {
        if (totalSupply() == 0) {
            super.deposit(assets, receiver);
            // TODO: gas golf this
            when = 0;
        } else {
            PendingDeposit storage pendingDeposit = pendingDepositOf[caller][receiver];

            // this is from msg.sender, NOT caller. i don't love that.
            SafeERC20.safeTransferFrom(IERC20(asset()), msg.sender, address(this), assets);

            // update counters - don't mint shares yet, calculate them at finalization
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

        uint256 prizeVaultShares = previewRedeem(fanTokenShares);

        IERC4626 prizeVault = IERC4626(asset());

        return prizeVault.previewRedeem(prizeVaultShares);
    }

    /// @notice override totalAssets to exclude pending deposits from the share price calculation
    function totalAssets() public view override returns (uint256) {
        uint256 actualAssets = super.totalAssets();
        // Subtract pending deposits so they don't affect the share price until finalized
        return actualAssets > totalPendingAssets ? actualAssets - totalPendingAssets : 0;
    }

    /// @notice prepare the auction contract for selling a token
    /// @dev this resets approvals to max (unlikely to be needed, but its a good safety measure)
    /// TODO: i feel like we should store a minimum trade amount here. but i don't know how to make that open. maybe this should be an only-owner function?
    function enableAuction(IERC20 from) public {
        IERC20 _asset = IERC20(asset());

        // don't allow auctioning the backing tokens! that would be bad!
        require(address(from) != address(this), InvalidAuctionToken());
        require(from != _asset, InvalidAuctionToken());
        require(from != UNDERLYING, InvalidAuctionToken());

        if (IAuction(auction).auctions(address(from)).scaler == 0) {
            IAuction(auction).enable(address(from));
        }

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
        IERC20 underlyingToken = UNDERLYING;

        if (address(UNDERLYING) == address(WETH)) {
            wrapETH();
        }

        // we want to use as much of the balance as possible
        underlyingAssets = underlyingToken.balanceOf(address(this));

        // calculate how many more tickets we can get
        uint256 maxDepositAssets = prizeVault.maxDeposit(address(this));

        if (underlyingAssets > maxDepositAssets) {
            // we leave any excess here.
            underlyingAssets = maxDepositAssets;

            // TODO: emit an event about having some excess tokens stuck
        }

        if (underlyingAssets == 0) {
            return underlyingAssets;
        }

        // TODO: I'm not sure these are right. i thought so, but my tests were giving weird answers for fees. so lets keep it simpler for now
        // uint256 expectedAssets = prizeVault.previewDeposit(underlyingAssets);
        // uint256 equivalentShares = previewDeposit(expectedAssets);

        uint256 assets = prizeVault.deposit(underlyingAssets, address(this));

        // optionally split some to a "treasury" address
        address treasuryAddress = TREASURY;
        if (treasuryAddress != address(0)) {
            uint256 treasuryFeeAssets =
                assets.mulDiv(harvestTreasuryFeeBasisPoints, _BASIS_POINT_SCALE, Math.Rounding.Floor);
            if (treasuryFeeAssets > 0) {
                // _mint(treasuryAddress, treasuryFeeShares);
                // set sponsorship status to ensure proper accounting
                // _setSponsorship(treasuryAddress, isSponsor[treasuryAddress]);

                // TODO: i'd prefer to mint fan tokens for these and keep them in this contract, but i can't get the math right
                IERC20(address(prizeVault)).safeTransfer(treasuryAddress, treasuryFeeAssets);

                // TODO: maybe if theres an allowance, we call _deposit? seems silly to be transferring around extra
            }
        }

        // optionally split some to an "owner" address
        // TODO: DRY. this is the same as the treasury code above
        address ownerAddress = owner();
        if (ownerAddress != address(0)) {
            uint256 ownerFeeAssets = assets.mulDiv(harvestOwnerFeeBasisPoints, _BASIS_POINT_SCALE, Math.Rounding.Floor);
            if (ownerFeeAssets > 0) {
                IERC20(address(prizeVault)).safeTransfer(ownerAddress, ownerFeeAssets);
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

            // burn the excess shares to redistribute rewards to non-sponsored token holders
            _update(address(this), address(0), amount);
        } else {}
    }

    /// @notice Returns the amount of underlying assets that can be harvested
    /// @dev Calculates harvestable amount without executing the harvest
    /// @return underlyingAssets Amount of underlying assets available for harvesting
    function harvestable() external view returns (uint256 underlyingAssets) {
        IERC4626 prizeVault = IERC4626(asset());
        IERC20 underlyingToken = UNDERLYING;

        // Calculate available balance (including any ETH if WETH)
        underlyingAssets = underlyingToken.balanceOf(address(this));
        if (address(UNDERLYING) == address(WETH)) {
            underlyingAssets += address(this).balance;
        }

        // Check vault deposit limits
        uint256 maxDepositAssets = prizeVault.maxDeposit(address(this));

        if (underlyingAssets > maxDepositAssets) {
            underlyingAssets = maxDepositAssets;
        }
    }

    /// @notice Returns the amount of sponsorship shares that can be harvested
    /// @dev Calculates excess shares that would be burned in harvestSponsorship
    /// @return amount Amount of excess shares that can be harvested
    function harvestableSponsorship() external view returns (uint256 amount) {
        uint256 correctShares = previewWithdraw(totalSponsorAssets);
        uint256 currentShares = balanceOf(address(this));

        if (currentShares > correctShares) {
            amount = currentShares - correctShares;
        } else {
            amount = 0;
        }
    }

    /**
     * @dev See {IERC4626-redeem}.
     */
    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256) {
        if (isSponsor[owner]) {
            uint256 ownerSponsorAssets = balanceOfSponsor[owner];
            uint256 assets = previewRedeem(shares);

            if (assets > ownerSponsorAssets) {
                uint256 availableShares = previewWithdraw(ownerSponsorAssets);
                revert InsufficientSponsorBalance(owner, ownerSponsorAssets, availableShares, assets, shares);
            }

            // Update sponsor accounting before moving shares
            balanceOfSponsor[owner] -= assets;
            totalSponsorAssets -= assets;

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

    function _setSponsorship(address who, bool state) internal {
        // todo? require msg.sender != owner() && msg.sender != TREASURY?
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
            balanceOfSponsor[from] -= assets;
            super._update(address(this), from, shares);

            super._update(from, to, shares);

            // update sponsorship accounting. this is probably overkill, but i think its safest
            _setSponsorship(from, true);
        } else if (toIsSponsor) {
            // from already holds shares.
            super._update(from, to, shares);

            // this will move the shares to this contract and update sponsorhip accounting
            _setSponsorship(to, true);
        } else {
            revert AtLeastOneSideMustBeSponsor();
        }
    }

    /// @dev i wanted to override `transfer` to work transparently, but that got too complicated quickly
    function sponsorTransfer(address to, uint256 assets) public returns (bool) {
        _sponsorTransfer(msg.sender, to, assets);
        return true;
    }

    /// @dev i wanted to override `transfer` to work transparently, but that got too complicated quickly
    function sponsorTransferFrom(address from, address to, uint256 assets) public returns (bool) {
        address spender = msg.sender;
        _spendAllowance(from, spender, previewWithdraw(assets));
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
            uint256 ownerSponsorAssets = balanceOfSponsor[owner];
            uint256 shares = previewWithdraw(assets);

            if (assets > ownerSponsorAssets) {
                uint256 availableShares = previewWithdraw(ownerSponsorAssets);
                revert InsufficientSponsorBalance(owner, ownerSponsorAssets, availableShares, assets, shares);
            }

            // Update sponsor accounting before moving shares
            balanceOfSponsor[owner] -= assets;
            totalSponsorAssets -= assets;

            super._update(address(this), owner, shares);
        }

        // approvals are checked here
        return super.withdraw(assets, receiver, owner);
    }

    /// TODO: this isn't really necessary
    function totalSponsoredShares() public view returns (uint256 shares) {
        shares = balanceOf(address(this));
    }

    /// TODO: this isn't really necessary
    function totalSponsoredAssets() public view returns (uint256 assets) {
        uint256 shares = totalSponsoredShares();
        assets = previewRedeem(shares);
    }

    // === minor helpers ===

    function version() external returns (string memory) {
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
