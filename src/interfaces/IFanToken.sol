// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {IWETH9, IERC20} from "v4-periphery/src/interfaces/external/IWETH9.sol";
import {IERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

interface IFanTokenFactory {
    function version() external returns (string memory);
}

interface IFanToken is IERC4626 {
    struct PendingDeposit {
        uint256 when;
        uint256 assets;
    }

    function FACTORY() external returns (IFanTokenFactory);
    function DEPOSIT_DELAY() external returns (uint256);

    function harvestOwnerFeeBasisPoints() external returns (uint256);
    function harvestTreasuryFeeBasisPoints() external returns (uint256);
    function treasury() external returns (address);
    function underlying() external returns (IERC20);
    function WETH() external returns (IWETH9);

    function burn(uint256 shares) external returns (uint256 assets);
    // TODO: should pending assets work like sponsor assets?
    function totalPendingAssets() external returns (uint256);
    // TODO: do we still need this?
    function totalSponsorAssets() external returns (uint256);
    function version() external returns (string memory);
}
