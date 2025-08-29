// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {IERC20, IERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

contract FanTokenZap {
    IERC20 immutable underlyingToken;
    IERC4626 immutable vaultToken;
    IERC4626 immutable fanToken;

    constructor(IERC4626 _fanToken) {
        vaultToken = IERC4626(fanToken.asset());
        underlyingToken = IERC20(vaultToken.asset());
    }
    
}
