// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {Bryan} from "../src/Bryan.sol";
// import {console} from "forge-std/console.sol";

contract BryanTest is Test {
    Bryan public bryan;

    function setUp() public {
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
}
