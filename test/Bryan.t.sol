// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {Bryan, ERC20} from "../src/Bryan.sol";
// import {console} from "forge-std/console.sol";

contract BryanTest is Test {
    uint256 baseFork;
    Bryan public bryan;

    function setUp() public {
        baseFork = vm.createFork("https://1rpc.io/base", 34771800);
        vm.selectFork(baseFork);

        address owner = address(this);

        // TODO: need a forked network!

        address prizePoolTwabRewards = 0xF4c47dacFda99bE38793181af9Fd1A2Ec7576bBF;
        address prizeVault = 0x7f5C2b379b88499aC2B997Db583f8079503f25b9;

        bryan = new Bryan(owner, prizePoolTwabRewards, prizeVault);
    }

    function test_ownership() public {
        address nextOwner = makeAddr("nextOwner");

        bryan.setNextOwner(nextOwner);

        vm.prank(nextOwner);
        bryan.claimOwnership();

        require(nextOwner == bryan.owner());
    }

    function test_deposit_and_withdraw() public {
        ERC20 asset = bryan.asset();

        uint256 assets = 1_000 * 1e6;

        deal(address(asset), address(this), assets, true);

        asset.approve(address(bryan), type(uint256).max);

        uint256 shares = bryan.deposit(assets);

        require(assets == shares);
        require(bryan.prizeVault().balanceOf(address(bryan)) == shares);
        require(bryan.balanceOf(address(this)) == assets);

        uint256 redeemed = bryan.redeem(shares, assets);

        require(redeemed == assets);
        require(bryan.prizeVault().balanceOf(address(bryan)) == 0);
        require(bryan.balanceOf(address(this)) == 0);
        require(asset.balanceOf(address(this)) == assets);
    }
}
