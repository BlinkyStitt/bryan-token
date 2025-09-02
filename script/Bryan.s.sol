// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {LibString} from "solady/utils/LibString.sol";
import {Script} from "forge-std/Script.sol";
import {FanToken, IERC4626, IWETH9} from "../src/FanToken.sol";

contract BryanScript is Script {
    using LibString for uint256;

    FanToken public bryan;

    function setUp() public {}

    function run() public {
        // constructor arguments
        address owner = 0x2699C32A793D58691419A054DA69414dF186b181;
        address prizePoolTwabRewards = 0xF4c47dacFda99bE38793181af9Fd1A2Ec7576bBF;
        IERC4626 prizeVault = IERC4626(0x7f5C2b379b88499aC2B997Db583f8079503f25b9); // TODO: this is the USDC vault. i want the WETH vault
        IWETH9 weth = IWETH9(address(0x4200000000000000000000000000000000000006));
        address treasury = address(0);

        uint256 entryFeeBasisPoints = 100;
        uint256 harvestOwnerFeeBasisPoints = 5000;
        uint256 harvestTreasuryFeeBasisPoints = 0;

        string memory addressPrefix = "0x0112358D";

        // prepare creation code
        bytes memory creationCode = abi.encodePacked(type(FanToken).creationCode, abi.encode(owner, prizeVault));

        bytes32 creationCodeHash = keccak256(creationCode);

        // find a salt. is it better to do this in deploy.sh or with ffi?
        // TODO: should we use a miner script like the uniswap deployer does? i think this is like 10x faster on my laptop
        string[] memory cmds = new string[](3);
        cmds[0] = "./script/salt_finder.sh";
        cmds[1] = addressPrefix;
        cmds[2] = LibString.toHexString(uint256(creationCodeHash), 32);
        bytes memory result = vm.ffi(cmds);

        bytes32 salt = abi.decode(result, (bytes32));

        // deploy the contract with our found salt
        vm.startBroadcast();
        bryan = new FanToken{salt: salt}(
            "ETH from Bryan",
            "BRY-ETH",
            entryFeeBasisPoints,
            harvestOwnerFeeBasisPoints,
            harvestTreasuryFeeBasisPoints,
            owner,
            prizeVault,
            treasury,
            weth
        );

        /*
        string memory _name,
        string memory _symbol,
        uint256 entryFeeBasisPoints,
        uint256 _harvestOwnerFeeBasisPoints,
        uint256 _harvestTreasuryFeeBasisPoints,
        address _owner,
        IERC4626 _prizeVault,
        address _treasury,
        IWETH9 _weth
        */

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
