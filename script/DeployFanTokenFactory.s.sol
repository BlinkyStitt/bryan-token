// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";
import {LibString} from "solady/utils/LibString.sol";
import {Script} from "forge-std/Script.sol";
import {FanTokenFactory, IWETH9} from "../src/FanTokenFactory.sol";
import {Generic4626Router} from "../src/interfaces/Generic4626Router.sol";

contract DeployFanTokenFactoryScript is Script {
    IWETH9 constant WETH9 = IWETH9(payable(0x4200000000000000000000000000000000000006));
    Generic4626Router constant GENERIC_4626_ROUTER = Generic4626Router(0xD60a6A0f0D5E3Fd451449C7256BbbDC59561e888);

    /// TODO: can we get this from config?
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    FanTokenFactory public fanTokenFactory;

    function setUp() public {}

    function run() public {
        string memory addressPrefix = "0x00FA00";

        // prepare creation code
        bytes memory creationCode =
            abi.encodePacked(type(FanTokenFactory).creationCode, abi.encode(GENERIC_4626_ROUTER, WETH9));

        bytes32 creationCodeHash = keccak256(creationCode);

        // find a salt. is it better to do this in deploy.sh or with ffi?
        // TODO: should we use a miner script like the uniswap deployer does? i think this is like 10x faster on my laptop
        string[] memory cmds = new string[](4);
        cmds[0] = "./script/salt_finder.sh";
        cmds[1] = LibString.toHexStringChecksummed(CREATE2_DEPLOYER);
        cmds[2] = addressPrefix;
        cmds[3] = LibString.toHexString(uint256(creationCodeHash), 32);
        bytes memory result = vm.ffi(cmds);

        bytes32 salt = abi.decode(result, (bytes32));

        // TODO: if the factory is already deployed at this address, what should we do?

        // deploy the contract with our found salt
        vm.startBroadcast();

        fanTokenFactory = new FanTokenFactory{salt: salt}(GENERIC_4626_ROUTER, WETH9);

        // make sure the address for the deployed contract matches the address prefix
        string memory fanTokenFactoryStringAddr =
            LibString.lower(LibString.toHexStringChecksummed(address(fanTokenFactory)));
        require(
            LibString.startsWith(fanTokenFactoryStringAddr, LibString.lower(addressPrefix)),
            "address prefix does not match"
        );

        console.log("Factory deployed to", address(fanTokenFactory));

        vm.stopBroadcast();
    }

    // TODO: script that prompts the user for all the "create" function params and then makes a token
}
