// SPDX-License-Identifier: UNLICENSED
// script to deploy the tokens for Bryan. TODO: make this configurable so anyone can use it
pragma solidity ^0.8.13;

import {LibString} from "solady/utils/LibString.sol";
import {Script} from "forge-std/Script.sol";
import {FanToken, FanTokenFactory, IERC20, IERC4626} from "../src/FanTokenFactory.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

// TODO: rewrite this to prompt the user for inputs instead of having everything hard coded
contract BryanScript is Script {
    using LibString for uint256;

    IERC4626 constant PRIZE_VAULT_USDC = IERC4626(0x7f5C2b379b88499aC2B997Db583f8079503f25b9);
    IERC4626 constant PRIZE_VAULT_WETH = IERC4626(0x4E42f783db2D0C5bDFf40fDc66FCAe8b1Cda4a43);

    FanTokenFactory public fanTokenFactory;
    address public owner;

    function setUp() public {
        // TODO: read the environment to get the contract address for the factory
        fanTokenFactory = FanTokenFactory(address(0));

        // TODO: is this right? how do we get the active account?
        owner = msg.sender;
    }

    function _deploy(
        string memory ownerName,
        string memory ownerSymbol,
        string memory addressPrefix,
        IERC4626 prizeVault,
        uint256 initialDeposit
    ) internal returns (FanToken fanToken) {
        uint256 harvestOwnerFeeBasisPoints = 5000;
        uint256 harvestTreasuryFeeBasisPoints = 0;
        address treasury = address(0);
        bool setupUniswapV4HookedPool = true;

        // prepare creation code
        // TODO: get creation code hash from a call to the factory. that should make sure things are definitely set correctly. these constructor args are incorrect!
        bytes memory creationCode =
            abi.encodePacked(type(FanToken).creationCode, abi.encode(address(this), PRIZE_VAULT_WETH));

        bytes32 creationCodeHash = keccak256(creationCode);

        // find a salt. is it better to do this in deploy.sh or with ffi?
        // TODO: should we use a miner script like the uniswap deployer does? i think this is like 10x faster on my laptop
        // TODO: this needs to be changed now that there is a factory contract doing the deploy
        string[] memory cmds = new string[](4);
        cmds[0] = "./script/salt_finder.sh";
        cmds[1] = LibString.toHexStringChecksummed(address(fanTokenFactory));
        cmds[2] = addressPrefix;
        cmds[3] = LibString.toHexString(uint256(creationCodeHash), 32);
        bytes memory result = vm.ffi(cmds);

        bytes32 salt = abi.decode(result, (bytes32));

        IERC20Metadata asset = IERC20Metadata(prizeVault.asset());

        string memory assetSymbol = asset.symbol();

        string memory name = string(abi.encodePacked(assetSymbol, " from ", ownerName));
        string memory symbol = string(abi.encodePacked(ownerSymbol, "-", assetSymbol));

        // deploy the contract with our found salt
        vm.startBroadcast();

        // approve if necessary for the initial deposit
        if (initialDeposit > prizeVault.allowance(owner, address(fanTokenFactory))) {
            prizeVault.approve(address(fanTokenFactory), type(uint256).max);
        }

        fanToken = fanTokenFactory.create(
            name,
            symbol,
            harvestOwnerFeeBasisPoints,
            harvestTreasuryFeeBasisPoints,
            prizeVault,
            treasury,
            salt,
            initialDeposit,
            setupUniswapV4HookedPool
        );

        // TODO: make sure the address for fanToken matches the address prefix

        vm.stopBroadcast();
    }

    function run() public {
        // TODO: constructor arguments should be function arguments i think
        string memory ownerName = "Bryan";
        string memory ownerSymbol = "BRY";

        string memory usdcAddressPrefix = "0xD8532110";
        string memory wethAddressPrefix = "0x0112358D";

        _deploy(ownerName, ownerSymbol, usdcAddressPrefix, PRIZE_VAULT_USDC, 0);
        _deploy(ownerName, ownerSymbol, wethAddressPrefix, PRIZE_VAULT_WETH, 0);
    }

    function claimPrize() public pure {
        revert(
            "claim any prizes. this might not be worth doing here. might be better to use pooltogether's official scirpts. research more"
        );
    }

    // TODO: this should probably be in another file
    function claimPool() public pure {
        revert("claim POOL if its over a threshold");
    }

    // TODO: this should probably be in another file
    function harvest() public pure {
        revert("claim WETH if its over a threshold");
    }

    function kickAuction() public pure {
        revert("start an auction for the relevant tokens (probably POOL)");
    }
}
