// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {LibString} from "solady/utils/LibString.sol";
import {Script} from "forge-std/Script.sol";
import {FanToken, FanTokenFactory, IERC4626, IWETH9} from "../src/FanTokenFactory.sol";

// TODO: rewrite this to prompt the user for inputs instead of having everything hard coded
contract BryanScript is Script {
    using LibString for uint256;

    FanTokenFactory public fanTokenFactory;
    FanToken public bryan;

    function setUp() public {}

    function run() public {
        // TODO: read the environment to get the contract address for the factory
        fanTokenFactory = FanTokenFactory(address(0));

        // constructor arguments
        address owner = 0x2699C32A793D58691419A054DA69414dF186b181; // TODO: use the active account
        address prizePoolTwabRewards = 0xF4c47dacFda99bE38793181af9Fd1A2Ec7576bBF;  // TODO: actually use this
        IERC4626 usdcPrizeVault = IERC4626(0x7f5C2b379b88499aC2B997Db583f8079503f25b9); // TODO: this is the USDC vault. i want the WETH vault
        IERC4626 wethPrizeVault = IERC4626(0x4E42f783db2D0C5bDFf40fDc66FCAe8b1Cda4a43);
        IWETH9 weth = IWETH9(address(0x4200000000000000000000000000000000000006));
        address treasury = address(0);

        uint256 entryFeeBasisPoints = 100;
        uint256 harvestOwnerFeeBasisPoints = 5000;
        uint256 harvestTreasuryFeeBasisPoints = 0;

        string memory addressPrefix = "0x0112358D";

        // prepare creation code
        revert("todo: this is wrong now. we need a helper function for checking salts from the factory");
        bytes memory creationCode = abi.encodePacked(type(FanToken).creationCode, abi.encode(owner, wethPrizeVault));

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
        uint256 initialDeposit = 0;

        // deploy the contract with our found salt
        vm.startBroadcast();

        // approve if necessary

        bryan = fanTokenFactory.create(
            "ETH from Bryan",
            "BRY-ETH",
            entryFeeBasisPoints,
            harvestOwnerFeeBasisPoints,
            harvestTreasuryFeeBasisPoints,
            wethPrizeVault,
            treasury,
            salt,
            initialDeposit
        );

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
