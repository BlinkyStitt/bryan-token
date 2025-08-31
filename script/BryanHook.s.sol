// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";

import {FanTokenUniswapV4Hook} from "../src/FanTokenUniswapV4Hook.sol";

/// @notice Mines the address and deploys the PointsHook.sol Hook contract
contract BryanUniswapV4HookScript is Script {
    function setUp() public {}

    function run() public {
        address poolmanager = 0x498581fF718922c3f8e6A244956aF099B2652b2b;

        // TODO: calculate this?
        address bryan = address(0);

        // TODO: is this available from config?
        address create2deployer = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

        // hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG);

        // function to make sure the flags here match our allowed hooks. I think OZ has a function for this

        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs = abi.encode(bryan, poolmanager);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(create2deployer, flags, type(FanTokenUniswapV4Hook).creationCode, constructorArgs);

        // Deploy the hook using CREATE2
        vm.broadcast();
        FanTokenUniswapV4Hook bryanHook = new FanTokenUniswapV4Hook{salt: salt}(bryan, IPoolManager(poolmanager));
        require(address(bryanHook) == hookAddress, "BryanUniswapV4HookScript: hook address mismatch");
    }
}
