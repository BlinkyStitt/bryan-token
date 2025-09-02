// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {AuctionSwapper} from "./forks/AuctionSwapper.sol";
import {ERC20, ERC4626, IERC20, IERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC4626EntryFees} from "./ERC4626EntryFees.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IWETH9} from "v4-periphery/src/interfaces/external/IWETH9.sol";

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

    function setupApprovals() public {
        underlying.forceApprove(asset(), type(uint256).max);
    }

    // === Custom things ===

    /// @notice check an account's balance in the underlying (backing) token
    function underlyingBalanceOf(address who) public view returns (uint256) {
        uint256 b = balanceOf(who);

        IERC4626 a = IERC4626(asset());

        return a.convertToAssets(b);
    }

    // TODO: we could write a mintUnderlying, but I don't think they are needed at this point. though maybe that exists as slippage protection?

    /// @notice harvest any ERC20 tokens as rewards. Tokens are split between the fan token, the owner, and the treasury.
    /// @dev I expect to call this with WETH and POOL after winning prizes
    /// @dev if you want to do something more complex with the coins, have that logic in the treasury contract
    /// @dev todo: have an option to harvest without swapping that opens up if a harvest with swapping hasn't happened for some time
    /// @dev todo: what should the return value be? this might have an async sale attached to it
    /// @dev if you harvest ETH with address(0), it will also harvest WETH.
    function harvest(IERC20 token) public returns (uint256 total) {
        // don't allow harvesting the backing token! that would be bad!
        IERC4626 assetToken = IERC4626(asset());
        require(token != assetToken, "!asset");

        // if token is 0x0, wrap any ETH in this contract
        if (address(this).balance > 0) {
            WETH.deposit{value: address(this).balance}();
        }

        // we want to use the entire balance
        total = token.balanceOf(address(this));
        if (total == 0) {
            return total;
        }

        IERC20 underlyingToken = underlying;
        if (token == underlyingToken) {
            // we are harvesting the underlying token. deposit it for the asset token
            total = assetToken.deposit(total, address(this));

            // optionally split some to a "treasury" address
            if (treasury != address(0)) {
                // TODO: which way should we round?
                uint256 treasuryFee =
                    total.mulDiv(harvestTreasuryFeeBasisPoints, _BASIS_POINT_SCALE, Math.Rounding.Ceil);
                if (treasuryFee > 0) {
                    IERC20(address(assetToken)).safeTransfer(treasury, treasuryFee);
                }
            }

            // optionally split some to an "owner" address
            address ownerAddress = owner();
            if (ownerAddress != address(0)) {
                // pay the owner part of the harvest
                // TODO: which way should we round?
                uint256 ownerFee = total.mulDiv(harvestOwnerFeeBasisPoints, _BASIS_POINT_SCALE, Math.Rounding.Ceil);
                if (ownerFee > 0) {
                    IERC20(address(assetToken)).safeTransfer(ownerAddress, ownerFee);
                }
            }

            // leave the remaining balance here. this will inflate the value of everyone's shares equally
        } else {
            // we can't deposit this token. we need to sell it into the underlying token so that we can compound it

            // this starts a dutch auction
            // TODO: should we just allow the owner to swap on aero/uniswap? i want a "can't be evil" design, so I think this is best
            // TODO: this can be DOSd. someone can send 1 wei and then call harvest! we need to check a minimum balance
            // TODO: if the owner is calling this and we already have an auction running, replace it?
            _enableAuction(address(token), address(underlyingToken));
        }
    }

    // === Auction functions ===

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
        // silence warnings about unused variables
        _amountTaken;
        _amountPayed;

        if (_token == address(underlying)) {
            harvest(IERC20(_token));
        }

        // TODO: should we do anything else here?
        // TODO: do a call in preTake that gets the price from an oracle and requires a minimum price from that? oracles are hard to get right
        // TODO: mark the current timestamp for this token. if this timestamp is too old, then we should allow harvesting without the auctions
        // TODO: if the auctions fails, where do the tokens end up?
        // TODO: what do we need to do on the auction contract so that it calls this post take function?
    }

    // === Fee configuration ===

    function _entryFeeBasisPoints() internal view override returns (uint256) {
        return __entryFeeBasisPoints;
    }

    function _entryFeeRecipient() internal view override returns (address) {
        return owner();
    }
}
