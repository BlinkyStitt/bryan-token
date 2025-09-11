// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {ERC20, IERC20, IERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IFanToken} from "./interfaces/IFanToken.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/*

This token holds onto fan tokens in a way that any profits can be burned

*/
contract SponsorToken is ERC20 {
    using SafeERC20 for IERC20;

    // TODO: do we need a full interface?
    IFanToken public immutable fanToken;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        fanToken = IFanToken(msg.sender);
    }

    /// @notice fanToken-only function for managing deposits.
    /// @dev the fan tokens MUST be transferred here before this is called.
    function _internalMint(address who, uint256 assets) public returns (uint256) {
        require(msg.sender == address(fanToken), "unauthorized");

        _mint(who, assets);
    }

    /// @notice fanToken-only function for managing redemptions
    function _internalBurn(address who, uint256 assets) public returns (uint256) {
        require(msg.sender == address(fanToken), "unauthorized");

        burnExcess();

        uint256 shares = fanToken.previewWithdraw(assets);

        IERC20(address(fanToken)).safeTransfer(who, assets);

        _burn(who, assets);
    }

    /// @notice burn sponsored tokens and credit them to all the other fan token holders
    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
        fanToken.burn(amount);
    }

    /// @notice send any rewards to the other token holders
    function burnExcess() public returns (uint256 amount) {
        uint256 correctShares = fanToken.previewWithdraw(totalSupply());

        uint256 currentShares = fanToken.balanceOf(address(this));

        if (currentShares > correctShares) {
            amount = currentShares - correctShares;
            fanToken.burn(amount);
        }
    }    
}
