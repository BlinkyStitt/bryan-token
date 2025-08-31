// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {FanToken, IERC20, IERC4626, IWETH9} from "../src/FanToken.sol";
import {console} from "forge-std/console.sol";

contract BryanTest is Test {
    uint256 baseFork;
    FanToken public bryan;

    function setUp() public {
        // TODO: use flags on the test command instead of forcing a fork here?
        baseFork = vm.createFork("https://1rpc.io/base");
        vm.selectFork(baseFork);

        address owner = address(this);

        IERC20 prizeVault = IERC20(0x7f5C2b379b88499aC2B997Db583f8079503f25b9);
        IWETH9 weth = IWETH9(address(0x4200000000000000000000000000000000000006));

        // tests are easier with fees off.
        uint256 compoundBasisPoints = 1e4;
        uint256 entryFeeBasisPoints = 0;
        uint256 harvestFeeBasisPoints = 0;

        bryan = new FanToken(
            "Fan of Bryan",
            "BRY",
            compoundBasisPoints,
            entryFeeBasisPoints,
            harvestFeeBasisPoints,
            owner,
            prizeVault,
            weth
        );
    }

    function test_ownership() public {
        address nextOwner = makeAddr("nextOwner");

        bryan.transferOwnership(nextOwner);

        // make sure acceptOwnership from other people fails
        vm.expectRevert();
        bryan.acceptOwnership();

        vm.prank(nextOwner);
        bryan.acceptOwnership();

        assertEq(nextOwner, bryan.owner(), "wrong new owner");
    }

    function test_deposit_and_withdraw() public {
        // TODO: for some reason we can't deal the ERC4626. We can deal the ERC20 though.
        IERC20 underlying = bryan.underlying();
        uint256 underlyingAssets = 1_000 * 1e6;
        deal(address(underlying), address(this), underlyingAssets, false);

        // asset == prize vault
        IERC4626 asset = IERC4626(bryan.asset());
        console.log("asset", address(asset));

        // approve and deposit the underlying to get the asset that backs Bryan
        underlying.approve(address(asset), type(uint256).max);
        uint256 assets = asset.deposit(underlyingAssets, address(this));

        // set up approvals
        asset.approve(address(bryan), type(uint256).max);

        // test the main deposit function
        uint256 shares = bryan.deposit(assets, address(this));

        // TODO: this require is wrong. we want to be sure that the shares we received are worth what we deposited
        // require(assets == shares);

        // TODO: the fees make this annoying
        assertEq(asset.balanceOf(address(bryan)), assets, "asset balance does not match assets");
        assertEq(bryan.balanceOf(address(this)), shares, "bryan balance does not match shares");

        // test the main redeem function
        uint256 redeemed = bryan.redeem(shares, address(this), address(this));

        // require(redeemed == assets);
        assertEq(IERC20(bryan.asset()).balanceOf(address(bryan)), 0, "token's asset balance should be empty");
        assertEq(bryan.balanceOf(address(this)), 0, "our balance of bryan should be empty");
        assertEq(asset.balanceOf(address(this)), assets, "we should have our asset back");
    }

    function test_deposit_and_withdraw_with_fees() public {
        bryan.setEntryFeeBasisPoints(5000);

        revert("todo: set fees");
    }

    function test_owner_only() public {
        revert("todo: make sure calling settings from the account that isn't the owner always fails");
    }

    function test_harvesting_pool() public {
        bryan.setHarvestFeeBasisPoints(5000);

        revert("todo: add some POOL to the contract and then sweep it. check fees");
    }

    function test_claiming_pool_rewards() public {
        revert("todo: claim POOL rewards");
    }

    function test_harvesting_weth() public {
        bryan.setHarvestFeeBasisPoints(5000);

        revert("todo: add some WETH to the contract and then sweep it. check fees");
    }

    function test_uniswap_v4_hook() public {
        revert("todo: create a uniswap v4 pool and a hook that wraps/unwraps the underlying token");
    }
}
