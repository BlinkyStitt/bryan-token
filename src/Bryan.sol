// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {ERC20, ERC4626, IERC20, IERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC4626EntryFees} from "./ERC4626EntryFees.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// WARNING: This contract has not been audited and shouldn't be considered production ready. Consider using it with caution.
contract Bryan is ERC4626EntryFees, Ownable2Step {
    using Math for uint256;
    using SafeERC20 for IERC20;

    uint256 private constant _BASIS_POINT_SCALE = 1e4;

    /// @dev 100 is 1%
    uint256 public harvestFeeBasisPoints;

    address public treasury;

    /// @dev 100 is 1%
    uint256 private __entryFeeBasisPoints;

    event NewTreasury(address indexed oldTreasury, address indexed newTreasury);

    constructor(uint256 entryFeeBasisPoints, uint256 _harvestFeeBasisPoints, address _owner, IERC20 _prizeVault)
        ERC20("Fan of Bryan", "BRY")
        ERC4626(_prizeVault)
        Ownable(_owner)
    {
        // these underscores are gross. too many different libraries and styles are being mixed together
        __entryFeeBasisPoints = entryFeeBasisPoints;
        harvestFeeBasisPoints = _harvestFeeBasisPoints;
        treasury = _owner;
    }

    // === getters ===

    /// @dev the asset inside of the prize vault. this is what most users will probably have to deposit
    function underlying() public view returns (IERC20 _underlying) {
        IERC4626 _asset = IERC4626(asset());
        _underlying = IERC20(payable(_asset.asset()));
    }

    // === owner-only functions ===

    /// @dev max possible is 20%
    function setEntryFeeBasisPoints(uint256 fee) public onlyOwner {
        require(fee <= 20 * _BASIS_POINT_SCALE);

        __entryFeeBasisPoints = fee;
    }

    /// @dev max possible is 90%
    function setHarvestFeeBasisPoints(uint256 fee) public onlyOwner {
        require(fee <= 90 * _BASIS_POINT_SCALE);

        harvestFeeBasisPoints = fee;
    }

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

        uint256 harvestFee = balance.mulDiv(harvestFeeBasisPoints, _BASIS_POINT_SCALE, Math.Rounding.Ceil);

        if (harvestFee > 0) {
            token.safeTransfer(owner(), harvestFee);
            balance -= harvestFee;
        }

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
