// TODO: do we need to
pragma solidity ^0.8.20;

import {ERC20, ERC4626, IERC20, IERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC4626EntryFees} from "./ERC4626EntryFees.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


/// @dev ERC-4626 vault with entry/exit fees expressed in https://en.wikipedia.org/wiki/Basis_point[basis point (bp)].
///
/// NOTE: The contract charges fees in terms of assets, not shares. This means that the fees are calculated based on the
/// amount of assets that are being deposited or withdrawn, and not based on the amount of shares that are being minted or
/// redeemed. This is an opinionated design decision that should be taken into account when integrating this contract.
///
/// WARNING: This contract has not been audited and shouldn't be considered production ready. Consider using it with caution.
contract Bryan is ERC4626EntryFees, Ownable2Step {
    using SafeERC20 for IERC20;

    address public treasury;

    event NewTreasury(address indexed oldTreasury, address indexed newTreasury);

    constructor(address _owner, IERC20 _prizeVault) ERC20("Bryan V3", "BRY3") ERC4626(_prizeVault) Ownable(_owner) {
        treasury = _owner;
    }

    // === getters ===

    /// @dev the asset inside of the prize vault. this is what most users will probably have to deposit
    function underlying() public view returns (IERC20 _underlying) {
        IERC4626 _asset = IERC4626(asset());
        _underlying = IERC20(payable(_asset.asset()));
    }

    // === owner-only functions ===

    function setTreasury(address newTreasury) public onlyOwner {
        emit NewTreasury(treasury, newTreasury);
        treasury = newTreasury;
    }

    // === Custom things ===

    /// @notice sweep ERC20 tokens out of this contract. 10% goes to owner and 90% goes to the treasury.
    /// @dev call this with WETH and POOL after winning prizes
    /// @dev if you want to do something more complex with the coins, have that logic in the treasury contract
    function harvest(IERC20 token) public returns (uint256 total) {
        total = token.balanceOf(address(this));

        if (total == 0) {
            return total;
        }

        uint256 balance = total;

        // TODO: make this configurable? (within some bounds. maybe only going down)
        uint256 ownerFee = balance / 10;

        if (ownerFee > 0) {
            token.safeTransfer(owner(), ownerFee);
            balance -= ownerFee;
        }

        token.safeTransfer(treasury, balance);
    }

    /// @notice deposit the underlying token
    /// @dev alternative names: depositUnderlying
    function zapIn(uint256 assets, address receiver) public returns (uint256 shares) {
        IERC4626 prizeVault = IERC4626(asset());
        IERC20 underlyingToken = IERC20(prizeVault.asset());

        underlyingToken.safeTransferFrom(msg.sender, address(this), assets);

        underlyingToken.approve(address(prizeVault), assets);

        uint256 vaultShares = prizeVault.deposit(assets, address(this));

        // TODO: do we need approvals for deposit to work? i hope not
        return deposit(vaultShares, receiver);
    }

    /// @notice withdraw the underlying token
    /// @dev alternative names: redeemUnderlying
    function zapOut(uint256 shares, uint256 minAssets) public returns (uint256 assets) {
        // these function names are confusing. our shares translate to their assets
        uint256 underlyingShares = _convertToAssets(shares, Math.Rounding.Floor);

        // TODO: how do we check the user's balance?
        // TODO: maybe the zaps should be in their own contract
        revert("wip");
    }

    // === Fee configuration ===

    // TODO: make this configurable by the owner. no more than 10%
    function _entryFeeBasisPoints() internal pure override returns (uint256) {
        return 0; // 100 is 1%
    }

    function _entryFeeRecipient() internal view override returns (address) {
        return owner();
    }
}
