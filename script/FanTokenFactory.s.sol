// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {LibString} from "solady/utils/LibString.sol";
import {Script} from "forge-std/Script.sol";
import {FanTokenFactory, IWETH9} from "../src/FanTokenFactory.sol";
import {Generic4626Router} from "../src/interfaces/Generic4626Router.sol";

contract FanTokenFactoryScript is Script {
    using LibString for uint256;

    IWETH9 constant WETH9 = IWETH9(payable(0x4200000000000000000000000000000000000006));
    Generic4626Router constant GENERIC_4626_ROUTER = Generic4626Router(0xD60a6A0f0D5E3Fd451449C7256BbbDC59561e888);

    FanTokenFactory public fanTokenFactory;

    function setUp() public {}

    function run() public {
        string memory addressPrefix = "0x00FA00";

        // prepare creation code
        bytes memory creationCode =
            abi.encodePacked(type(FanTokenFactory).creationCode, abi.encode(WETH9, GENERIC_4626_ROUTER));

        bytes32 creationCodeHash = keccak256(creationCode);

        // find a salt. is it better to do this in deploy.sh or with ffi?
        // TODO: should we use a miner script like the uniswap deployer does? i think this is like 10x faster on my laptop
        // TODO: this needs to be changed now that there is a factory contract doing the deploy
        string[] memory cmds = new string[](3);
        cmds[0] = "./script/salt_finder.sh";
        cmds[1] = addressPrefix;
        cmds[2] = LibString.toHexString(uint256(creationCodeHash), 32);
        bytes memory result = vm.ffi(cmds);

        bytes32 salt = abi.decode(result, (bytes32));

        // deploy the contract with our found salt
        vm.startBroadcast();
        fanTokenFactory = new FanTokenFactory{salt: salt}(WETH9, GENERIC_4626_ROUTER);

        // TODO: make sure the address for the deployed contract matches the address prefix

        vm.stopBroadcast();
    }

    // TODO: script that prompts the user for all the "create" function params and then makes a token
}
