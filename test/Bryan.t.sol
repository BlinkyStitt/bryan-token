// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {stdJson} from "forge-std/StdJson.sol";
import {Test} from "forge-std/Test.sol";
import {Bryan, Base64, LibString} from "../src/Bryan.sol";
import {console} from "forge-std/console.sol";

contract BryanTest is Test {
    using stdJson for string;

    Bryan public bryan;

    function setUp() public {
        string memory name = "Bryan";
        string memory symbol = "BRY";
        string memory description = "Just for fun.";
        string memory image =
            "https://wrpcd.net/cdn-cgi/imagedelivery/BXluQx4ige9GuW0Ia56BHw/41b5bebd-f3b0-4c85-c465-bd62cd947c00/anim=false,fit=contain,f=auto,w=128";
        string memory website = "https://farcaster.xyz/flashprofits.eth";
        uint8 decimals = 0;
        uint256 initialSupply = 10_000;

        address owner = address(this);

        bryan = new Bryan(name, symbol, description, image, website, owner, decimals, initialSupply);
    }

    function test_description() public {
        bryan.setDescription("new description");
        assertEq(bryan.description(), "new description");
    }

    function test_image() public {
        bryan.setImage("new image");
        assertEq(bryan.image(), "new image");
    }

    function test_website() public {
        bryan.setWebsite("new website");
        assertEq(bryan.website(), "new website");
    }

    function test_billboard() public {
        bryan.yoink("new billboard");
        assertEq(bryan.billboard(), "new billboard");
    }

    function test_ownership() public {
        address nextOwner = makeAddr("nextOwner");

        bryan.setNextOwner(nextOwner);

        vm.prank(nextOwner);
        bryan.claimOwnership();

        require(nextOwner == bryan.owner());
    }

    function test_uri() public view {
        string memory uri = bryan.tokenURI();

        // 2. Strip prefix
        string memory encoded = vm.replace(uri, "data:application/json;base64,", "");

        // 3. Base64 decode to JSON
        bytes memory decoded = Base64.decode(encoded);

        string memory json = string(decoded);

        console.logString(json);

        // 4. Cheatcode-based JSON parsing
        string memory name = json.readString(".name");
        string memory symbol = json.readString(".symbol");
        string memory decimals = json.readString(".decimals");
        string memory description = json.readString(".description");
        string memory image = json.readString(".image");
        string memory website = json.readString(".website");

        assertEq(name, "Bryan");
        assertEq(symbol, "BRY");
        assertEq(decimals, "0");
        assertEq(description, "Just for fun.");
        assertEq(
            image,
            "https://wrpcd.net/cdn-cgi/imagedelivery/BXluQx4ige9GuW0Ia56BHw/41b5bebd-f3b0-4c85-c465-bd62cd947c00/anim=false,fit=contain,f=auto,w=128"
        );
        assertEq(website, "https://farcaster.xyz/flashprofits.eth");
    }
}
