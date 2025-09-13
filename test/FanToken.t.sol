// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {InvalidAuctionToken, FanToken, IERC20, IERC4626, IWETH9} from "../src/FanToken.sol";
import {Auction} from "../src/forks/AuctionSwapper.sol";
import {console} from "forge-std/console.sol";

contract FanTokenTest is Test {
    FanToken public bryan;
    address treasury;
    IWETH9 weth;
    address owner;
    address factory;

    function setUp() public {
        // TODO: use flags on the test command instead of forcing a fork here?
        owner = makeAddr("bryan owner");

        IERC4626 prizeVault = IERC4626(0x4E42f783db2D0C5bDFf40fDc66FCAe8b1Cda4a43);
        weth = IWETH9(address(0x4200000000000000000000000000000000000006));

        // TODO: the entry fee isn't what i want. i want it to be in fanTokens, not in underlying!

        // fees of 0 are probably too simple to be worthwhile. need to test with actual fees set
        uint256 harvestOwnerFeeBasisPoints = 0;
        uint256 harvestTreasuryFeeBasisPoints = 0;
        treasury = makeAddr("treasury");
        factory = makeAddr("factory");

        vm.prank(factory);
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

    /// @dev make sure the vault's underlying is weth
    function test_vault_asset() public {
        assertEq(address(bryan.underlying()), address(weth), "underlying isn't weth");
    }

    /// @dev coverage for supply and assets
    function test_vault_starts_empty() public {
        assertEq(bryan.totalSupply(), 0);
        assertEq(bryan.totalAssets(), 0);
    }

    function test_ownership() public {
        address nextOwner = makeAddr("nextOwner");

        console.log("changing ownership from", owner, "to", nextOwner);

        assertEq(owner, bryan.owner());

        // make sure random accounts can't call transferOwnership
        vm.expectRevert();
        bryan.transferOwnership(nextOwner);

        // only the owner should be able to call transfer ownership
        vm.prank(owner);
        bryan.transferOwnership(nextOwner);

        // make sure acceptOwnership from other people fails
        vm.expectRevert();
        bryan.acceptOwnership();

        // only the next owner should be able to accept ownership
        vm.prank(nextOwner);
        bryan.acceptOwnership();

        // make sure the owner changed
        assertEq(nextOwner, bryan.owner(), "wrong new owner");
    }

    /// @dev helper function for turning underlying assets into erc4626 shares
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

    function test_expected_default_sponsors() public {
        assertEq(bryan.isSponsor(address(0)), false);
        assertEq(bryan.isSponsor(address(bryan)), false); // TODO: i'm unsure if we want this to be true or not. i think not
        assertEq(bryan.isSponsor(owner), true);
        assertEq(bryan.isSponsor(treasury), true);
        assertEq(bryan.isSponsor(factory), true);
    }


    function test_multiple_users_depositing_without_sponsorship() public {
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        address charlie = makeAddr("charlie");

        // TODO: pick multiple amounts. and have users take different amounts. this should find any problems with rounding
        uint256 underlyingAssets = 1 ether;

        (IERC4626 asset, uint256 assets) = _dealAsset(underlyingAssets * 4, address(this));

        uint256 quarterAssets = assets / 4;
        console.log("quarter assets:", quarterAssets);

        require(asset.transfer(alice, quarterAssets));
        require(asset.transfer(bob, quarterAssets));
        require(asset.transfer(charlie, quarterAssets));

        // todo: there might be 1 wei. i think thats fine
        assertEq(asset.balanceOf(address(this)), quarterAssets, "assets should have been sent to alice/bob/charlie");

        // get some tokens for alice
        vm.startPrank(alice);
        asset.approve(address(bryan), type(uint256).max);
        uint256 aliceWhen = bryan.startDeposit(quarterAssets);
        assertEq(aliceWhen, 0, "first deposit should be instant");

        uint256 aliceFanTokens = bryan.balanceOf(alice);
        console.log("alice's fan tokens:", aliceFanTokens);

        // check balances
        assertEq(bryan.balanceOfUnderlying(alice), quarterAssets, "alice initial deposit should work");
        assertEq(bryan.balanceOfUnderlying(bob), 0, "bob should have zero");
        assertEq(bryan.balanceOfUnderlying(charlie), 0, "charlie should have zero");
        // TODO: what is the balance expected to be?

        // check sponsorship levels
        assertEq(bryan.isSponsor(alice), false, "alice must not be a sponsor");
        assertEq(bryan.isSponsor(bob), false, "bob must be a sponsor");
        assertEq(bryan.isSponsor(charlie), false, "charlie must not be a sponsor");

        // get some sponsor tokens for bob
        vm.startPrank(bob);
        asset.approve(address(bryan), type(uint256).max);
        uint256 bobWhen = bryan.startDeposit(quarterAssets);
        assertEq(bobWhen, block.timestamp + bryan.DEPOSIT_DELAY(), "unexpected deposit delay");

        // check balances
        assertEq(bryan.balanceOfUnderlying(alice), quarterAssets, "alice initial deposit should work");
        assertEq(bryan.balanceOfUnderlying(bob), 0, "bob should have zero");
        assertEq(bryan.balanceOfUnderlying(charlie), 0, "charlie should have zero");

        assertEq(bryan.balanceOfSponsor(alice), 0, "alice should not have a sponsor balance");
        assertEq(bryan.balanceOfSponsor(bob), 0, "bob should not have a sponsor balance");
        assertEq(bryan.balanceOfSponsor(charlie), 0, "charlie should not have a sponsor balance");

        // TODO: this name should include "assets". and then balanceOfPending should be in shares.
        assertEq(bryan.balanceOfPending(alice), 0, "alice should not have a pending balance");
        assertEq(bryan.balanceOfPending(bob), quarterAssets, "bob should have a pending balance");
        assertEq(bryan.balanceOfPending(charlie), 0, "charlie should not have a pending balance");

        // fast forward and finalize deposit
        vm.warp(block.timestamp + bryan.DEPOSIT_DELAY());
        uint256 bobFanTokens = bryan.deposit(quarterAssets, address(bob));
        console.log("bob's fan tokens:", bobFanTokens);

        assertEq(bryan.balanceOfUnderlying(alice), quarterAssets, "alice initial deposit should work");
        assertEq(bryan.balanceOfUnderlying(bob), quarterAssets, "bob should have a deposit now");
        assertEq(bryan.balanceOfUnderlying(charlie), 0, "charlie should still have zero");

        assertEq(bryan.balanceOfSponsor(alice), 0, "alice should still not have a sponsor balance");
        assertEq(bryan.balanceOfSponsor(bob), 0, "bob should still not have a sponsor balance now");
        assertEq(bryan.balanceOfSponsor(charlie), 0, "charlie should still not have a sponsor balance");

        // get some tokens for charlie and then convert them to sponsor tokens
        vm.startPrank(charlie);
        asset.approve(address(bryan), type(uint256).max);
        uint256 charlieWhen = bryan.startDeposit(quarterAssets);

        assertEq(charlieWhen, block.timestamp + bryan.DEPOSIT_DELAY(), "charlie deposit delay wrong");

        // TODO: add some rewards to the contract and make sure that doesn't break any balances

        // fast forward and finalize deposit
        vm.warp(block.timestamp + bryan.DEPOSIT_DELAY());
        uint256 charlieFanTokens = bryan.deposit(quarterAssets, address(charlie));
        console.log("charlie's fan tokens:", charlieFanTokens);

        assertEq(bryan.balanceOfUnderlying(alice), quarterAssets, "alice should still have their original deposit");
        assertEq(bryan.balanceOfUnderlying(bob), quarterAssets, "bob should still have their original deposit");
        assertEq(bryan.balanceOfUnderlying(charlie), quarterAssets, "charlie should now have a deposit");

        assertEq(bryan.balanceOfSponsor(alice), 0, "after charlie, alice should still not have a sponsor balance");
        assertEq(bryan.balanceOfSponsor(bob), 0, "after charlie, bob should still not have a sponsor balance");
        assertEq(bryan.balanceOfSponsor(charlie), 0, "after charlie, charlie should still not have a sponsor balance");

        // TODO: transfer tokens from alice to bob
        // TODO: transfer tokens from alice to charlie
        // TODO: transfer tokens from bob to alice
        // TODO: transfer tokens from bob to charlie
        // TODO: transfer tokens from charlie to alice
        // TODO: transfer tokens from charlie to bob
    }

    function test_multiple_users_depositing_with_sponsorship() public {
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        address charlie = makeAddr("charlie");

        // TODO: pick multiple amounts. and have users take different amounts. this should find any problems with rounding
        uint256 underlyingAssets = 1 ether;

        (IERC4626 asset, uint256 assets) = _dealAsset(underlyingAssets * 4, address(this));

        uint256 quarterAssets = assets / 4;
        console.log("quarter assets:", quarterAssets);

        require(asset.transfer(alice, quarterAssets));
        require(asset.transfer(bob, quarterAssets));
        require(asset.transfer(charlie, quarterAssets));

        // todo: there might be 1 wei. i think thats fine
        assertEq(asset.balanceOf(address(this)), quarterAssets, "assets should have been sent to alice/bob/charlie");

        // get some tokens for alice
        vm.startPrank(alice);
        asset.approve(address(bryan), type(uint256).max);
        uint256 aliceWhen = bryan.startDeposit(quarterAssets);
        assertEq(aliceWhen, 0, "first deposit should be instant");

        uint256 aliceFanTokens = bryan.balanceOf(alice);
        console.log("alice's fan tokens:", aliceFanTokens);

        // check balances
        assertEq(bryan.balanceOfUnderlying(alice), quarterAssets, "alice initial deposit should work");
        assertEq(bryan.balanceOfUnderlying(bob), 0, "bob should have zero");
        assertEq(bryan.balanceOfUnderlying(charlie), 0, "charlie should have zero");
        // TODO: what is the balance expected to be?

        // mark bob as a sponsor
        vm.startPrank(bob);
        bryan.setSponsorship(true);

        // check sponsorship levels
        assertEq(bryan.isSponsor(alice), false, "alice must not be a sponsor");
        assertEq(bryan.isSponsor(bob), true, "bob must be a sponsor");
        assertEq(bryan.isSponsor(charlie), false, "charlie must not be a sponsor");

        // get some sponsor tokens for bob
        asset.approve(address(bryan), type(uint256).max);
        uint256 bobWhen = bryan.startDeposit(quarterAssets);
        assertEq(bobWhen, block.timestamp + bryan.DEPOSIT_DELAY(), "unexpected deposit delay");

        // check balances
        assertEq(bryan.balanceOfUnderlying(alice), quarterAssets, "alice initial deposit should work");
        assertEq(bryan.balanceOfUnderlying(bob), 0, "bob should have zero");
        assertEq(bryan.balanceOfUnderlying(charlie), 0, "charlie should have zero");

        assertEq(bryan.balanceOfSponsor(alice), 0, "alice should not have a sponsor balance");
        assertEq(bryan.balanceOfSponsor(bob), 0, "bob should not have a sponsor balance");
        assertEq(bryan.balanceOfSponsor(charlie), 0, "charlie should not have a sponsor balance");

        // TODO: this name should include "assets". and then balanceOfPending should be in shares.
        assertEq(bryan.balanceOfPending(alice), 0, "alice should not have a pending balance");
        assertEq(bryan.balanceOfPending(bob), quarterAssets, "bob should have a pending balance");
        assertEq(bryan.balanceOfPending(charlie), 0, "charlie should not have a pending balance");

        // fast forward and finalize deposit
        vm.warp(block.timestamp + bryan.DEPOSIT_DELAY());
        uint256 bobFanTokens = bryan.deposit(quarterAssets, address(bob));
        console.log("bob's fan tokens:", bobFanTokens);

        assertEq(bryan.balanceOfUnderlying(alice), quarterAssets, "alice initial deposit should work");
        assertEq(bryan.balanceOfUnderlying(bob), 0, "bob should still have zero");
        assertEq(bryan.balanceOfUnderlying(charlie), 0, "charlie should still have zero");

        assertEq(bryan.balanceOfSponsor(alice), 0, "alice should still not have a sponsor balance");
        assertEq(bryan.balanceOfSponsor(bob), quarterAssets, "bob should have a sponsor balance now");
        assertEq(bryan.balanceOfSponsor(charlie), 0, "charlie should still not have a sponsor balance");

        // get some tokens for charlie and then convert them to sponsor tokens
        vm.startPrank(charlie);
        asset.approve(address(bryan), type(uint256).max);
        uint256 charlieWhen = bryan.startDeposit(quarterAssets);

        assertEq(charlieWhen, block.timestamp + bryan.DEPOSIT_DELAY(), "charlie deposit delay wrong");

        // we change set sponsorship during the delay queue
        // TODO: we should also have a test that changes sponsorship after the deposit is finalized
        bryan.setSponsorship(true);

        // TODO: add some rewards to the contract and make sure that doesn't break any balances

        // fast forward and finalize deposit
        vm.warp(block.timestamp + bryan.DEPOSIT_DELAY());
        uint256 charlieFanTokens = bryan.deposit(quarterAssets, address(charlie));
        console.log("charlie's fan tokens:", charlieFanTokens);

        assertEq(bryan.balanceOfUnderlying(alice), quarterAssets, "alice should still have their original deposit");
        assertEq(bryan.balanceOfUnderlying(bob), 0, "bob is a sponsor and should have zero still");
        assertEq(bryan.balanceOfUnderlying(charlie), 0, "charlie is a sponsor and should should still have zero still");

        assertEq(bryan.balanceOfSponsor(alice), 0, "after charlie, alice should still not have a sponsor balance");
        assertEq(bryan.balanceOfSponsor(bob), quarterAssets, "after charlie, bob should have a sponsor balance now");
        assertEq(bryan.balanceOfSponsor(charlie), quarterAssets, "after charlie, charlie should have a sponsor balance now");

        // TODO: transfer tokens from alice to bob
        // TODO: transfer tokens from alice to charlie
        // TODO: transfer tokens from bob to alice
        // TODO: transfer tokens from bob to charlie
        // TODO: transfer tokens from charlie to alice
        // TODO: transfer tokens from charlie to bob

        // TODO: turn off bob's sponsorship? we need a test that just does a single sponsor user back and forth
    }

    function test_toggle_sponsorship() public {
        uint256 underlyingAssets = 1 ether;
        console.log("underlyingAssets:", underlyingAssets, "ether");

        (IERC4626 asset, uint256 assets) = _dealAsset(underlyingAssets, address(this));
        console.log("assets:", assets, address(asset));

        asset.approve(address(bryan), type(uint256).max);
        uint256 when = bryan.startDeposit(assets);

        assertEq(when, 0, "this deposit should be instant");

        uint256 originalTotalSupply = bryan.totalSupply();
        console.log("total supply:", originalTotalSupply);

        assertEq(bryan.balanceOfUnderlying(address(this)), underlyingAssets, "initial deposit amount");
        assertEq(bryan.balanceOfSponsor(address(this)), 0, "initial deposit amount shouldn't have any sponsorship");
        assertEq(bryan.totalAssets(), assets, "initial deposit assets");
        assertGt(originalTotalSupply, 0, "there should be some total supply");

        bryan.setSponsorship(true);

        assertEq(bryan.balanceOfUnderlying(address(this)), 0, "initial deposit amount");
        assertEq(bryan.balanceOfSponsor(address(this)), underlyingAssets, "now it should have sponsorship");
        assertEq(bryan.totalAssets(), assets, "total assets should be unchanged");
        assertEq(bryan.totalSupply(), originalTotalSupply, "total supply should be unchanged");

        bryan.setSponsorship(false);

        assertEq(bryan.balanceOfUnderlying(address(this)), underlyingAssets, "initial deposit amount");
        assertEq(bryan.balanceOfSponsor(address(this)), 0, "now it should have sponsorship");
        assertEq(bryan.totalAssets(), assets, "total assets should still be unchanged");
        assertEq(bryan.totalSupply(), originalTotalSupply, "total supply should be still unchanged");
    }

    function test_deposit_and_withdraw() public {
        // TODO: for some reason we can't deal the ERC4626. We can deal the ERC20 though.
        uint256 underlyingAssets = 1 ether;
        (IERC4626 asset, uint256 assets) = _dealAsset(underlyingAssets, address(this));

        uint256 depositDelay = bryan.DEPOSIT_DELAY();

        // set up approvals
        asset.approve(address(bryan), type(uint256).max);

        // TODO: test startDeposit!
        // time travel to start and complete a deposit
        // TODO: check the logs
        // bryan.startDeposit(assets, address(this));
        // assertEq(assets, bryan.pendingBalanceOf(address(this)), "wrong pending balance");
        // assertEq(assets, bryan.totalPendingDeposits(), "wrong total pending balance");

        uint256 shares = bryan.deposit(assets / 2, address(this));
        console.log(shares, "shares for", assets / 2, "assets");
        assertEq(shares, assets / 2, "initial deposit failed");

        assertEq(bryan.totalSupply(), shares, "supply wrong 1");

        // todo: deposit without calling start should revert
        uint256 when = bryan.startDeposit(assets / 2, address(this));
        console.log("second deposit of", assets / 2, "assets available at", when);
        assertEq(when, block.timestamp + depositDelay, "startDeposit failed");
        assertEq(bryan.balanceOfPending(address(this)), assets / 2, "finishing deposit failed");

        // Total supply should not increase until deposit is finalized
        assertEq(bryan.totalSupply(), shares, "supply should stay same until deposit finalized");

        /*
        // switch sponsoring on while a deposit is pending. i think this is broken
        console.log("enabling sponsorship");
        bryan.setSponsorship(true);

        // TODO: assert some things about balances
        assassertApproxEqAbsertEq(bryan.balanceOfSponsor(address(this)), assets / 2, 1, "first sponsor balance is wrong");
        */

        vm.warp(block.timestamp + depositDelay);
        // TODO: test depositing from another address. anyone should be able to finalize a deposit
        uint256 newShares = bryan.deposit(assets / 2, address(this));
        console.log("shares from second deposit:", newShares);

        /*
        assertApproxEqAbs(bryan.balanceOfSponsor(address(this)), assets, 1, "second sponsor balance is wrong");

        // switch sponsoring off
        console.log("disabling sponsorship");
        bryan.setSponsorship(false);
        */

        assertEq(bryan.balanceOfPending(address(this)), 0, "finishing deposit failed");

        assertEq(bryan.totalSupply(), shares + newShares, "supply wrong 3");

        // TODO: the fees make this annoying
        // TODO: make sure that the balance of the prize vault grew by the underlying assets
        assertEq(asset.balanceOf(address(bryan)), assets, "asset balance does not match assets");
        assertEq(bryan.balanceOf(address(this)), shares + newShares, "bryan balance does not match shares");
        assertApproxEqAbs(
            bryan.balanceOfUnderlying(address(this)), underlyingAssets, 1, "underlying balance does not match"
        );

        // test the main redeem function
        uint256 redeemed = bryan.redeem(shares + newShares, address(this), address(this));
        console.log("redeemed", shares + newShares, "shares into", redeemed);

        assertGt(redeemed, 0, "none redeemed"); // TODO: what should this amount be?
        assertApproxEqAbs(
            IERC20(bryan.asset()).balanceOf(address(bryan)), 0, 1, "token's asset balance should be empty"
        );
        assertEq(bryan.balanceOf(address(this)), 0, "our balance of bryan should be empty");
        assertApproxEqAbs(asset.balanceOf(address(this)), assets, 1, "we should have our asset back less the fee");
        assertEq(bryan.balanceOfUnderlying(address(this)), 0, "underlying balance is not zeroed");
    }

    function test_auctioning_asset_fails() public {
        IERC20 from = IERC20(bryan.asset());

        vm.expectRevert(InvalidAuctionToken.selector);
        bryan.enableAuction(from);
    }

    function test_auctioning_underlying_fails() public {
        IERC20 from = IERC20(address(bryan.underlying()));

        vm.expectRevert(InvalidAuctionToken.selector);
        bryan.enableAuction(from);
    }

    function test_auctioning_self_fails() public {
        IERC20 from = IERC20(address(bryan));

        vm.expectRevert(InvalidAuctionToken.selector);
        bryan.enableAuction(from);
    }

    function test_post_take_blocked() public {
        // vm.assume(sender != address(0));
        // vm.assume(sender != address(bryan));

        IERC20 from = IERC20(0xd652C5425aea2Afd5fb142e120FeCf79e18fafc3); // POOL

        // call enable action once to create the auction contract
        bryan.enableAuction(from);

        address auction = bryan.auction();
        require(auction != address(0), "auction not set");

        vm.expectRevert();
        bryan.postTake(address(0), 0, 0);
    }

    function test_auctioning_pool() public {
        IERC20 prizeVault = IERC20(bryan.asset());
        console.log("prizeVault:", address(prizeVault));

        IERC20 from = IERC20(0xd652C5425aea2Afd5fb142e120FeCf79e18fafc3); // POOL

        bytes32 auctionId = bryan.enableAuction(from);

        uint256 fromAmount = 1 ether;
        console.log("fromAmount", fromAmount);

        deal(address(from), address(bryan), fromAmount, true);

        assertEq(bryan.kickable(address(from)), fromAmount, "kickable amount wrong");

        Auction auction = Auction(bryan.auction());
        require(address(auction) != address(0), "no auction contract");

        // TODO: do we need to approvals here? i don't think so
        uint256 available = auction.kick(auctionId);

        assertEq(fromAmount, available, "auction size incorrect");

        // TODO: wait until a specific price?
        vm.warp(block.timestamp + 12 hours);

        address want = auction.want();
        console.log("want:", want);

        uint256 auctionAmountNeeded = auction.getAmountNeeded(auctionId, fromAmount);
        console.log("auction amount needed:", auctionAmountNeeded, want);
        assertGt(auctionAmountNeeded, 0, "want amount should be nonzero");

        assertEq(want, address(bryan.underlying()), "wrong want");

        // cheat to have the necessary tokens to fulfill the auction
        weth.deposit{value: auctionAmountNeeded}();

        IERC20(want).approve(address(auction), auctionAmountNeeded);
        uint256 amountFromTaken = auction.take(auctionId);
        console.log("amountFromTaken:", amountFromTaken, want);

        assertEq(amountFromTaken, fromAmount, "from amount error");

        // thanks to the post take hook, this was deposited
        assertEq(IERC20(want).balanceOf(address(bryan)), 0);

        // TODO: i don't like this amount being hard coded.
        assertEq(prizeVault.balanceOf(address(bryan)), 244140625000000000000);
    }

    function test_empty_harvest() public {
        assertEq(bryan.harvest(), 0);
    }

    function test_harvest_eth() public {
        require(address(bryan.underlying()) == address(weth), "not weth");

        uint256 amount = 1 ether;

        assertEq(bryan.harvest{value: amount}(), amount, "incorrect eth harvest amount");
    }

    function test_harvest_weth() public {
        require(address(bryan.underlying()) == address(weth), "not weth");

        uint256 amount = 1 ether;

        weth.deposit{value: amount}();
        bool success = weth.transfer(address(bryan), amount);

        require(success, "weth transfer failed");

        assertEq(bryan.harvest(), amount, "incorrect weth harvest amount");
    }

    function test_wrapping_eth(uint256 value) public {
        // TODO: what is the actual max? something involving weth's totalSupply
        vm.assume(value < 100 ether);
        vm.assume(value > 0); // we call wrapETH at the start and end, so no real point in skipping it

        assertEq(bryan.wrapETH(), 0);
        assertEq(weth.balanceOf(address(bryan)), 0);

        assertEq(bryan.wrapETH{value: value}(), value);
        assertEq(weth.balanceOf(address(bryan)), value);

        assertEq(bryan.wrapETH(), 0);
        assertEq(weth.balanceOf(address(bryan)), value);
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

    test_finish_deposit

    test_auction_post_take

    test_enable_auction

    test_no_mint

    test_burn
    */
}
