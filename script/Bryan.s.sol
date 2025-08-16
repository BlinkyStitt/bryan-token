// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {Bryan} from "../src/Bryan.sol";

contract BryanScript is Script {
    Bryan public bryan;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        bryan = new Bryan();

        vm.stopBroadcast();
    }
}
