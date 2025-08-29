// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {IERC20, IERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

contract FanTokenZap {

    IERC4626 immutable fanToken;
    IERC4626 immutable vaultToken;
    IERC20 immutable underlyingToken;

    constructor(IERC4626 _fanToken) {
        fanToken = _fanToken;
        vaultToken = IERC4626(_fanToken.asset());
        underlyingToken = IERC20(vaultToken.asset());
    }
    
    function zapIn(uint256 assets, address receiver) public {
        revert("wip");
    }

    function zapOut(uint256 shares, address receiver, uint256 minAssets) public { 
        revert("wip");
    }
}
