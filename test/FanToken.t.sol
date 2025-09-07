// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {InvalidAuctionToken, FanToken, IERC20, IERC4626, IWETH9} from "../src/FanToken.sol";
import {console} from "forge-std/console.sol";

contract BryanTest is Test {
    FanToken public bryan;
    address treasury;
    IWETH9 weth;
    address owner;

    function setUp() public {
        // TODO: use flags on the test command instead of forcing a fork here?
        owner = makeAddr("bryan owner");

        IERC4626 prizeVault = IERC4626(0x4E42f783db2D0C5bDFf40fDc66FCAe8b1Cda4a43);
        weth = IWETH9(address(0x4200000000000000000000000000000000000006));

        // TODO: the entry fee isn't what i want. i want it to be in fanTokens, not in underlying!

        // fees of 0 are probably too simple to be worthwhile. need to test with actual fees set
        uint256 entryFeeBasisPoints = 0;
        uint256 harvestOwnerFeeBasisPoints = 0;
        uint256 harvestTreasuryFeeBasisPoints = 0;
        treasury = makeAddr("treasury");

        bryan = new FanToken(
            "ETH from Bryan",
            "BRY-ETH",
            harvestOwnerFeeBasisPoints,
            harvestTreasuryFeeBasisPoints,
            owner,
            prizeVault,
            treasury,
            weth
        );
    }

    function test_vault_asset() public {
        assertEq(address(bryan.underlying()), address(weth), "underlying isn't weth");
    }

    function test_vault_starts_empty() public {
        assertEq(bryan.totalSupply(), 0);
        assertEq(bryan.totalAssets(), 0);
    }

    function test_ownership() public {
        address nextOwner = makeAddr("nextOwner");

        vm.prank(owner);
        bryan.transferOwnership(nextOwner);

        // make sure acceptOwnership from other people fails
        vm.expectRevert();
        bryan.acceptOwnership();

        vm.prank(nextOwner);
        bryan.acceptOwnership();

        assertEq(nextOwner, bryan.owner(), "wrong new owner");
    }

    function _dealAsset(uint256 underlyingAssets, address receiver) internal returns (IERC4626 asset, uint256 assets) {
        IERC20 underlying = bryan.underlying();
        deal(address(underlying), address(this), underlyingAssets, false);

        // asset == prize vault
        asset = IERC4626(bryan.asset());
        console.log("asset", address(asset));

        // approve and deposit the underlying to get the asset that backs Bryan
        underlying.approve(address(asset), type(uint256).max);
        assets = asset.deposit(underlyingAssets, receiver);
    }

    function test_deposit_and_withdraw() public {
        // TODO: for some reason we can't deal the ERC4626. We can deal the ERC20 though.
        uint256 underlyingAssets = 1_000 * 1e6;
        (IERC4626 asset, uint256 assets) = _dealAsset(underlyingAssets, address(this));

        // set up approvals
        asset.approve(address(bryan), type(uint256).max);

        // TODO: test startDeposit!
        // time travel to start and complete a deposit
        // TODO: check the logs
        // bryan.startDeposit(assets, address(this));
        // assertEq(assets, bryan.pendingBalanceOf(address(this)), "wrong pending balance");
        // assertEq(assets, bryan.totalPendingDeposits(), "wrong total pending balance");

        // vm.warp(block.timestamp + bryan.DEPOSIT_DELAY() + 1);
        uint256 shares = bryan.deposit(assets, address(this));

        // shares should currently be 1:1
        assertEq(shares, underlyingAssets, "bad deposit");

        // TODO: this require is wrong. we want to be sure that the shares we received are worth what we deposited
        // require(assets == shares);

        // TODO: the fees make this annoying
        // TODO: make sure that the balance of the prize vault grew by the underlying assets
        assertEq(asset.balanceOf(address(bryan)), assets, "asset balance does not match assets");
        assertEq(bryan.balanceOf(address(this)), shares, "bryan balance does not match shares");
        assertEq(bryan.balanceOfUnderlying(address(this)), underlyingAssets, "underlying balance does not match");

        // test the main redeem function
        uint256 redeemed = bryan.redeem(shares, address(this), address(this));

        assertGt(redeemed, 0, "none redeemed"); // TODO: what should this amount be?
        assertEq(IERC20(bryan.asset()).balanceOf(address(bryan)), 0, "token's asset balance should be empty");
        assertEq(bryan.balanceOf(address(this)), 0, "our balance of bryan should be empty");
        assertEq(asset.balanceOf(address(this)), assets, "we should have our asset back less the fee");
        assertEq(bryan.balanceOfUnderlying(address(this)), 0, "underlying balance is not zeroed");
    }

    function test_auctioning_asset_fails() public {
        IERC20 asset = IERC20(bryan.asset());

        vm.expectRevert(InvalidAuctionToken.selector);
        bryan.enableAuction(asset);
    }

    /*
    function test_harvesting_pool() public {
        // bryan.setHarvestFeeBasisPoints(5000);

        revert("todo: add some POOL to the contract and then sweep it. check fees");
    }

    function test_deposit_and_withdraw_with_fees() public {
        revert("todo: deploy a contract with fees and then try deposit/withdraw on it");
    }

    function test_owner_only() public {
        revert("todo: make sure calling settings from the account that isn't the owner always fails");
    }


    function test_claiming_pool_rewards() public {
        revert("todo: claim POOL rewards on pooltogether's contract");
    }

    function test_harvesting_weth() public {
        // bryan.setHarvestFeeBasisPoints(5000);

        revert("todo: add some WETH to the contract and then sweep it. check fees");
    }

    function test_uniswap_v4_hook() public {
        revert(
            "todo: create a uniswap v4 pool and a hook that wraps/unwraps the underlying token. make sure two pools with our hooks can be combined"
        );
        // TODO: what are some other options? what do
    }
    */
}
