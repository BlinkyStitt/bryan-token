// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {LibString} from "@solady/utils/LibString.sol";
import {Script} from "forge-std/Script.sol";
import {Bryan, IERC20} from "../src/Bryan.sol";

contract BryanScript is Script {
    using LibString for uint256;

    Bryan public bryan;

    function setUp() public {}

    function run() public {
        // constructor arguments
        address owner = 0x2699C32A793D58691419A054DA69414dF186b181;
        address prizePoolTwabRewards = 0xF4c47dacFda99bE38793181af9Fd1A2Ec7576bBF;
        IERC20 prizeVault = IERC20(0x7f5C2b379b88499aC2B997Db583f8079503f25b9);

        string memory addressPrefix = "0x0112358D";

        // prepare creation code
        bytes memory creationCode = abi.encodePacked(type(Bryan).creationCode, abi.encode(owner, prizeVault));

        bytes32 creationCodeHash = keccak256(creationCode);

        // find a salt. is it better to do this in deploy.sh or with ffi?
        string[] memory cmds = new string[](3);
        cmds[0] = "./script/salt_finder.sh";
        cmds[1] = addressPrefix;
        cmds[2] = LibString.toHexString(uint256(creationCodeHash), 32);
        bytes memory result = vm.ffi(cmds);

        bytes32 salt = abi.decode(result, (bytes32));

        // deploy the contract with our found salt
        vm.startBroadcast();
        bryan = new Bryan{salt: salt}(owner, prizeVault);

        // TODO: make sure the address for bryan matches the address prefix

        vm.stopBroadcast();
    }

    // TODO: this should probably be in another file
    function claimPool() public pure {
        revert("claim POOL if its over a threshold");
        revert("sweep the POOL to the owner");
        // originally, i wanted to send the POOL to the treasury, but the treasury only seems to want white listed assets
    }

    // TODO: this should probably be in another file
    function harvest() public pure {
        revert("claim WETH if its over a threshold");
    }

    // TODO: this should probably be in another file
    function sweep() public pure {
        revert("sweep an arbitrary token");
    }
}
