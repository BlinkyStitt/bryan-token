// SPDX-License-Identifier: UNLICENSED
// script to deploy the tokens for Bryan. TODO: make this configurable so anyone can use it
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {LibString} from "solady/utils/LibString.sol";
import {Script} from "forge-std/Script.sol";
import {FanToken, FanTokenFactory, IERC4626} from "../src/FanTokenFactory.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

// TODO: rewrite this to prompt the user for inputs instead of having everything hard coded
contract DeployBryanScript is Script, StdCheats {
    using LibString for uint256;

    // these are the addresses on Base. Maybe these should be from config, but this is enough for me for now
    // most users will use our mini-app, not this script anyways.
    IERC4626 constant PRIZE_VAULT_USDC = IERC4626(0x7f5C2b379b88499aC2B997Db583f8079503f25b9);
    IERC4626 constant PRIZE_VAULT_WETH = IERC4626(0x4E42f783db2D0C5bDFf40fDc66FCAe8b1Cda4a43);

    FanTokenFactory public fanTokenFactory;

    function setUp() public {
        // Read factory address from deployment artifacts for current chain
        string memory chainId = vm.toString(block.chainid);
        string memory path = string.concat("./broadcast/DeployFanTokenFactory.s.sol/", chainId, "/run-latest.json");
        string memory json = vm.readFile(path);
        address factoryAddr = vm.parseJsonAddress(json, ".transactions[0].contractAddress");
        fanTokenFactory = FanTokenFactory(factoryAddr);
    }

    // TODO: i can't decide if this should take arguments, or just be hard coded for me. i expect users to use a mini-app, not these scripts
    function run() public {
        console.log("sender:", msg.sender);

        string memory ownerName = "Bryan";
        string memory ownerSymbol = "BRY";

        // string memory usdcAddressPrefix = "0x8532110";
        // string memory wethAddressPrefix = "0x0112358";
        string memory usdcAddressPrefix = "0x00AB00"; // TODO: remove before flight!
        string memory wethAddressPrefix = "0x00CD00"; // TODO: remove before flight!

        IERC20Metadata usdc = IERC20Metadata(PRIZE_VAULT_USDC.asset());
        // IERC20Metadata weth = IERC20Metadata(PRIZE_VAULT_WETH.asset());

        uint256 usdcInitialDeposit = block.chainid == 18543 ? 0 : 200 * 10 ** usdc.decimals();
        _deploy(ownerName, ownerSymbol, usdcAddressPrefix, PRIZE_VAULT_USDC, usdcInitialDeposit);

        _deploy(ownerName, ownerSymbol, wethAddressPrefix, PRIZE_VAULT_WETH, 0.05 ether);
    }

    // TODO: i can't decide if this should take more arguments, or just be hard coded for me. i expect users to use a mini-app, not these scripts
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
        bool setupUniswapV4HookedPool = false;  // TODO: remove before flight

        IERC20Metadata underlying = IERC20Metadata(prizeVault.asset());

        string memory underlyingSymbol = underlying.symbol();

        console.log("underlyingSymbol:", underlyingSymbol);

        bool underlyingIsWeth = LibString.eq(underlyingSymbol, "WETH");

        string memory name = string(abi.encodePacked(underlyingSymbol, " from ", ownerName));
        string memory symbol = string(abi.encodePacked(ownerSymbol, "-", underlyingSymbol));

        console.log("fan token name:", name);
        console.log("fan token symbol:", symbol);

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
        console.log("salt:", LibString.toHexString(uint256(salt)));

        // TODO: if the token is already deployed with these parameters, what should we do?

        if (underlyingIsWeth) {
            // check ETH balance. the create command can handle the wrapping
            require(msg.sender.balance >= initialDeposit, "not enough ETH for the initial deposit!");
        } else {
            // check the token balance
            require(underlying.balanceOf(msg.sender) >= initialDeposit, "not enough tokens for the initial deposit!");
        }
        console.log("balance checks passed for", msg.sender);

        // deploy the contract with our found salt
        vm.startBroadcast();

        // approve if necessary for the initial deposit
        if (underlyingIsWeth) {
            // no approvals needed for weth. we send native ETH
        } else if (initialDeposit > underlying.allowance(msg.sender, address(fanTokenFactory))) {
            // TODO: max approval, or initialDeposit approval?
            console.log("approvals needed");
            require(underlying.approve(address(fanTokenFactory), type(uint256).max), "approval of underlying failed");
        } else {
            console.log("approvals already set");
        }

        uint256 valueForCreate;
        if (underlyingIsWeth) {
            console.log("Sending ETH instead of WETH");
            valueForCreate = initialDeposit;
        }

        fanToken = fanTokenFactory.create{value: valueForCreate}(
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

        console.log(fanToken.symbol(), "deployed to", address(fanToken));

        // make sure the address for the deployed contract matches the address prefix
        // TODO: case sensitive prefixes seem like a waste of time
        string memory fanTokenStringAddr = LibString.lower(LibString.toHexStringChecksummed(address(fanToken)));
        require(
            LibString.startsWith(fanTokenStringAddr, LibString.lower(addressPrefix)), "address prefix does not match"
        );

        vm.stopBroadcast();
    }
}
