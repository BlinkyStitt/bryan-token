// SPDX-License-Identifier: AGPL-3.0-only
// it seems safer to isolate tokens in different contracts rather than do more complicated accounting inside of a single contract.
pragma solidity ^0.8.20;

import {ERC20, IERC20, IERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IFanToken} from "./interfaces/IFanToken.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/*

This token holds onto fan tokens in a way that any profits can be burned

*/
contract DepositQueue {
    using SafeERC20 for IERC20;

    IFanToken public immutable fanToken;

    /// @dev this should be deployed by the FanToken!
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        fanToken = IFanToken(msg.sender);
    }

    function _update(address from, address to, uint256 amount) internal override {
        if (from != address(0) && to != address(0)) {
            revert("transfers are not allowed");
        }

        self._update(from, to, amount);
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


        uint256 shares = fanToken.previewWithdraw(assets);

        IERC20(address(fanToken)).safeTransfer(who, assets);

        _burn(who, assets);

        burnExcess();
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

    /// @notice start a delayed deposit to prevent shenanigans
    function startDeposit(uint256 assets, address receiver) returns (uint256 when) {
        if (fanToken.totalSupply() == 0) {
            uint256 shares = fanToken.deposit(assets, receiver);
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

    function finishDeposit()
}