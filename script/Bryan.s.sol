// SPDX-License-Identifier: UNLICENSED
// script to deploy the tokens for Bryan. TODO: make this configurable so anyone can use it
pragma solidity ^0.8.13;

import {LibString} from "solady/utils/LibString.sol";
import {Script} from "forge-std/Script.sol";
import {FanToken, FanTokenFactory, IERC4626} from "../src/FanTokenFactory.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

// TODO: rewrite this to prompt the user for inputs instead of having everything hard coded
contract BryanScript is Script {
    using LibString for uint256;

    IERC4626 constant PRIZE_VAULT_USDC = IERC4626(0x7f5C2b379b88499aC2B997Db583f8079503f25b9);
    IERC4626 constant PRIZE_VAULT_WETH = IERC4626(0x4E42f783db2D0C5bDFf40fDc66FCAe8b1Cda4a43);

    FanTokenFactory public fanTokenFactory;

    function setUp() public {
        // Read factory address from deployment artifacts for current chain
        string memory chainId = vm.toString(block.chainid);
        string memory path = string.concat("./broadcast/FanTokenFactory.s.sol/", chainId, "/run-latest.json");
        string memory json = vm.readFile(path);
        address factoryAddr = vm.parseJsonAddress(json, ".transactions[0].contractAddress");
        fanTokenFactory = FanTokenFactory(factoryAddr);
    }

    function _deploy(
        string memory ownerName,
        string memory ownerSymbol,
        string memory addressPrefix,
        IERC4626 prizeVault,
        uint256 initialDeposit
    ) internal returns (FanToken fanToken) {
        // half the rewards go to the owner.
        uint256 harvestOwnerFeeBasisPoints = 5000;
        uint256 harvestTreasuryFeeBasisPoints = 0;
        address treasury = address(0);
        bool setupUniswapV4HookedPool = true;

        IERC20Metadata asset = IERC20Metadata(prizeVault.asset());

        string memory assetSymbol = asset.symbol();

        string memory name = string(abi.encodePacked(assetSymbol, " from ", ownerName));
        string memory symbol = string(abi.encodePacked(ownerSymbol, "-", assetSymbol));

        bytes32 salt;
        if (LibString.eq(addressPrefix, "0x")) {
            salt = bytes32(0);
        } else {
            // prepare creation code
            bytes32 creationCodeHash = fanTokenFactory.createCodeHash(
                name, symbol, harvestOwnerFeeBasisPoints, harvestTreasuryFeeBasisPoints, prizeVault, treasury
            );

            // find a salt. is it better to do this in deploy.sh or with ffi?
            // TODO: should we use a miner script like the uniswap deployer does? i think this is like 10x faster on my laptop
            // TODO: this needs to be changed now that there is a factory contract doing the deploy
            string[] memory cmds = new string[](4);
            cmds[0] = "./script/salt_finder.sh";
            cmds[1] = LibString.toHexStringChecksummed(address(fanTokenFactory));
            cmds[2] = addressPrefix;
            cmds[3] = LibString.toHexString(uint256(creationCodeHash), 32);
            bytes memory result = vm.ffi(cmds);

            salt = abi.decode(result, (bytes32));
        }

        // deploy the contract with our found salt
        vm.startBroadcast();

        // approve if necessary for the initial deposit
        if (initialDeposit > prizeVault.allowance(msg.sender, address(fanTokenFactory))) {
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

    function runWETH(
        string calldata ownerName,
        string calldata ownerSymbol,
        string calldata usdcAddressPrefix,
        string calldata wethAddressPrefix
    ) public {}

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
