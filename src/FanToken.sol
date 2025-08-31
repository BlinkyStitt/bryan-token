// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {ERC20, ERC4626, IERC20, IERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC4626EntryFees} from "./ERC4626EntryFees.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IWETH9} from "v4-periphery/src/interfaces/external/IWETH9.sol";

/// @notice WARNING: This contract has not been audited and shouldn't be considered production ready. Proceed with caution.
contract FanToken is ERC4626EntryFees, Ownable2Step {
    using Math for uint256;
    using SafeERC20 for IERC20;

    uint256 private constant _BASIS_POINT_SCALE = 1e4;

    /// @dev 100 is 1%
    uint256 public harvestFeeBasisPoints;

    address public treasury;

    IERC20 public immutable underlying;

    IWETH9 public immutable WETH;

    /// @notice the owner gets a portion of all deposits. A core design choice of this token is to make it easy to tip the owner.
    /// @dev 100 is 1%. Deposits send this percent to the owner.
    /// @dev I don't like how this doesn't match the pattern for the others. i want this to just be uint256 public entryFeeBasisPoints;
    uint256 private __entryFeeBasisPoints;

    /// @notice token holders get to keep some of the rewards
    /// @dev 100 is 1%
    uint256 public compoundBasisPoints;

    event NewTreasury(address indexed oldTreasury, address indexed newTreasury);
    // TODO: events for the fees changing

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _compoundBasisPoints,
        uint256 entryFeeBasisPoints,
        uint256 _harvestFeeBasisPoints,
        address _owner,
        IERC4626 _prizeVault,
        IWETH9 _weth
    ) ERC20(_name, _symbol) ERC4626(_prizeVault) Ownable(_owner) {
        require(_compoundBasisPoints + entryFeeBasisPoints + _harvestFeeBasisPoints <= _BASIS_POINT_SCALE);

        underlying = IERC20(_prizeVault.asset());

        // these underscores are gross. too many different libraries and styles are being mixed together
        compoundBasisPoints = _compoundBasisPoints;
        __entryFeeBasisPoints = entryFeeBasisPoints;
        harvestFeeBasisPoints = _harvestFeeBasisPoints;
        treasury = _owner;
        WETH = _weth;
    }

    /// @dev allow receiving eth
    receive() external payable {}

    // TODO: pricePerShareUnderlying() (with a better name)

    // === owner-only functions ===

    /// @dev max possible is 100%
    function setCompoundBasisPoints(uint256 fee) public onlyOwner {
        require(fee <= 100 * 100);
        // TODO: require that the total of the fees is <= 100%

        __entryFeeBasisPoints = fee;

        // TODO: timelock on the fees changing
    }

    /// @dev max possible is 50%
    function setEntryFeeBasisPoints(uint256 fee) public onlyOwner {
        require(fee <= 50 * 100);
        // TODO: require that the total of the fees is <= 100%

        __entryFeeBasisPoints = fee;

        // TODO: timelock on the fees changing
    }

    /// @dev max possible is 90%
    function setHarvestFeeBasisPoints(uint256 fee) public onlyOwner {
        require(fee <= 90 * 100);
        // TODO: require that the total of the fees is <= 100%

        harvestFeeBasisPoints = fee;

        // TODO: timelock on the fees changing
    }

    /// @dev some funds get sent to an Empire Builder treasury. These funds will be shared with the top 10-250 holders (TBD).
    function setTreasury(address newTreasury) public onlyOwner {
        emit NewTreasury(treasury, newTreasury);
        treasury = newTreasury;
    }

    // === Custom things ===

    function underlyingBalanceOf(address who) public returns (uint256) {
        uint256 b = balanceOf(who);

        IERC4626 a = IERC4626(asset());

        return a.convertToAssets(b);
    }

    /**
     * @dev See {IERC4626-deposit}.
     */
    function depositUnderlying(uint256 underlyingAssets, address receiver) public virtual returns (uint256) {
        IERC20 underlyingToken = underlying;

        // TODO: think about the approvals for this
        // TODO: what does the _msgSender() thing do again?
        underlyingToken.safeTransferFrom(_msgSender(), address(this), underlyingAssets);

        IERC4626 vaultToken = IERC4626(asset());

        // TODO: set up infinite approval on start instead?
        underlyingToken.approve(address(vaultToken), underlyingAssets);
        uint256 assets = vaultToken.deposit(underlyingAssets, address(this));

        uint256 maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
        }

        uint256 shares = previewDeposit(assets);
        _deposit(address(this), receiver, assets, shares);

        return shares;
    }

    /**
     * @dev See {IERC4626-mint}.
     */
    function mintUnderlying(uint256 shares, address receiver) public returns (uint256) {
        revert("todo: convert the underlying");

        uint256 maxShares = maxMint(receiver);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxMint(receiver, shares, maxShares);
        }

        uint256 assets = previewMint(shares);
        _deposit(_msgSender(), receiver, assets, shares);

        return assets;
    }

    /**
     * @dev See {IERC4626-withdraw}.
     */
    function withdrawUnderlying(uint256 assets, address receiver, address owner) public returns (uint256) {
        uint256 maxAssets = maxWithdraw(owner);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxWithdraw(owner, assets, maxAssets);
        }

        uint256 shares = previewWithdraw(assets);
        _withdraw(_msgSender(), receiver, owner, assets, shares);

        revert("todo: convert to the underlying");

        return shares;
    }

    /**
     * @dev See {IERC4626-redeem}.
     */
    function redeemUnderlying(uint256 shares, address receiver, address owner) public returns (uint256) {
        uint256 maxShares = maxRedeem(owner);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxRedeem(owner, shares, maxShares);
        }

        uint256 assets = previewRedeem(shares);
        _withdraw(_msgSender(), receiver, owner, assets, shares);

        revert("todo: convert to the underlying");

        return assets;
    }

    /// @notice harvest any ERC20 tokens as rewards. Tokens are split between the fan token, the owner, and the treasury.
    /// @dev I expect to call this with WETH and POOL after winning prizes
    /// @dev
    /// @dev if you want to do something more complex with the coins, have that logic in the treasury contract
    function harvest(IERC20 token) public returns (uint256 total) {
        // don't allow harvesting the backing token! that would be bad!
        IERC20 assetToken = IERC20(asset());
        require(token != assetToken, "!asset");

        // if token is 0x0, wrap any ETH in this contract and harvest as WETH
        if (address(token) == address(0)) {
            WETH.deposit{value: address(this).balance}();
            token = WETH;
        }

        // we want to use the entire balance
        total = token.balanceOf(address(this));
        if (total == 0) {
            return total;
        }

        // if we are harvesting the underlying token, we should deposit it for the asset token
        IERC20 underlyingToken = underlying;
        uint256 balance;
        if (token == underlyingToken) {
            total = depositUnderlying(total, address(this));
            token = assetToken;

            // TODO: which way should we round?
            uint256 compoundAmount = total.mulDiv(compoundBasisPoints, _BASIS_POINT_SCALE, Math.Rounding.Floor);

            // no transfer. we keep the coins here. this will inflate the value of everyone's shares equally
            balance -= compoundAmount;
        } else {
            // TODO: sell the tokens for the underlying using a dutch auction. Yearn has some really interesting contracts for this.
            balance = total;
        }

        // pay the owner part of the harvest
        // TODO: which way should we round?
        uint256 ownerFee = total.mulDiv(harvestFeeBasisPoints, _BASIS_POINT_SCALE, Math.Rounding.Ceil);
        if (ownerFee > 0) {
            token.safeTransfer(owner(), ownerFee);
            balance -= ownerFee;
        }

        // send the rest of the balance to the treasury. we take the full balance so theres no chance of rounding errors
        if (balance > 0) {
            token.safeTransfer(treasury, balance);
        }
    }

    // === Fee configuration ===

    function _entryFeeBasisPoints() internal view override returns (uint256) {
        return __entryFeeBasisPoints;
    }

    function _entryFeeRecipient() internal view override returns (address) {
        return owner();
    }
}
