// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {BryanSol} from "../src/Bryan.sol";

contract BryanTest is Test {
    BryanSol public bryan;

    function setUp() public {
        string memory name = "Bryan";
        string memory symbol = "BRY";
        string memory description = "Just for fun.";
        string memory website = "https://farcaster.xyz/flashprofits.eth";
        string memory image = "https://wrpcd.net/cdn-cgi/imagedelivery/BXluQx4ige9GuW0Ia56BHw/b0b01cf5-fc8d-479b-074a-1a09c3270d00/anim=false,fit=contain,f=auto,w=576";
        uint8 decimals;
        uint256 initialSupply = 10_000;

        bryan = new BryanSol(name, symbol, description, image, website, decimals, initialSupply);
    }

    function test_uri() public view {
        string memory uri = bryan.tokenURI();

        // TODO: parse it as json and do things with it
    }
}
