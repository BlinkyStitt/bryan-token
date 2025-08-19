// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {Bryan, LibString} from "../src/Bryan.sol";

contract BryanScript is Script {
    using LibString for uint256;

    Bryan public bryan;

    function setUp() public {}

    function run() public {
        // constructor arguments
        string memory name = "Bryan";
        string memory symbol = "BRY";
        string memory description = "Just for fun.";
        string memory website = "https://farcaster.xyz/flashprofits.eth";
        string memory image =
            "https://wrpcd.net/cdn-cgi/imagedelivery/BXluQx4ige9GuW0Ia56BHw/41b5bebd-f3b0-4c85-c465-bd62cd947c00/anim=false,fit=contain,f=auto,w=128";
        uint8 decimals = 18;
        uint256 initialSupply = 10_000 * 10 ** decimals;
        address owner = 0x2699C32A793D58691419A054DA69414dF186b181;

        string memory addressPrefix = "0x0112358";

        // prepare creation code
        bytes memory creationCode = abi.encodePacked(type(Bryan).creationCode, abi.encode(name, symbol, description, image, website, owner, decimals, initialSupply));

        bytes32 creationCodeHash = keccak256(creationCode);

        // find a salt
        string[] memory cmds = new string[](3);
        cmds[0] = "./script/salt_finder.sh";
        cmds[1] = addressPrefix;
        cmds[2] = LibString.toHexString(uint256(creationCodeHash), 32);
        bytes memory result = vm.ffi(cmds);

        bytes32 salt = abi.decode(result, (bytes32));

        // deploy the contract with our found salt
        vm.startBroadcast();
        bryan = new Bryan{salt: salt}(name, symbol, description, image, website, owner, decimals, initialSupply);

        // TODO: make sure the address for bryan matches the address prefix

        vm.stopBroadcast();
    }
}
