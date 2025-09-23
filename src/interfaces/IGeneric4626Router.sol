// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";

// Minimal interface for the deployed Generic4626Router contract
interface IGeneric4626Router {
    function initializePool(address vault) external returns (PoolKey memory poolKey, PoolId poolId);
    function poolManager() external view returns (address);
    function poolDetails(PoolId poolId) external view returns (bool isInitialized, bool wrapsZeroToOne);
}
