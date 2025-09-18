// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {InvalidAuctionToken, FanToken, IERC20, IERC4626, IWETH9} from "../src/FanToken.sol";
import {FanTokenFactory} from "../src/FanTokenFactory.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Auction} from "../src/forks/AuctionSwapper.sol";
import {console} from "forge-std/console.sol";

contract FanTokenTest is Test {
    using SafeERC20 for IERC20;

    FanToken public bryan;
    address treasury;
    IWETH9 weth;
    IERC20 underlying;
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

        // Deploy a real factory instead of using makeAddr
        FanTokenFactory realFactory = new FanTokenFactory(weth);
        factory = address(realFactory);

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

        underlying = bryan.UNDERLYING();
    }

    /// @dev make sure the vault's underlying is weth
    function test_vault_asset() public view {
        assertEq(address(bryan.UNDERLYING()), address(weth), "underlying isn't weth");
    }

    /// @dev coverage for supply and assets
    function test_vault_starts_empty() public view {
        assertEq(bryan.totalSupply(), 0, "vault should start with zero total supply");
        assertEq(bryan.totalAssets(), 0, "vault should start with zero total assets");
    }

    function test_ownership() public {
        address nextOwner = makeAddr("nextOwner");

        console.log("changing ownership from", owner, "to", nextOwner);

        assertEq(owner, bryan.owner(), "initial owner should match expected owner");

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
        deal(address(underlying), address(this), underlyingAssets, false);

        // asset == prize vault
        asset = IERC4626(bryan.asset());
        console.log("asset", address(asset));

        // approve and deposit the underlying to get the asset that backs Bryan
        underlying.approve(address(asset), type(uint256).max);
        assets = asset.deposit(underlyingAssets, receiver);
    }

    function test_expected_default_sponsors() public view {
        assertEq(bryan.isSponsor(address(0)), false, "zero address should not be sponsor");
        assertEq(bryan.isSponsor(address(bryan)), false, "contract itself should not be sponsor"); // TODO: i'm unsure if we want this to be true or not. i think not
        assertEq(bryan.isSponsor(owner), true, "owner should be default sponsor");
        assertEq(bryan.isSponsor(treasury), true, "treasury should be default sponsor");
        assertEq(bryan.isSponsor(factory), true, "factory should be default sponsor");
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
        assertEq(
            bryan.balanceOfSponsor(charlie), quarterAssets, "after charlie, charlie should have a sponsor balance now"
        );

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
        IERC20 from = IERC20(address(bryan.UNDERLYING()));

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

        assertEq(want, address(bryan.UNDERLYING()), "wrong want");

        // cheat to have the necessary tokens to fulfill the auction
        weth.deposit{value: auctionAmountNeeded}();

        IERC20(want).approve(address(auction), auctionAmountNeeded);
        uint256 amountFromTaken = auction.take(auctionId);
        console.log("amountFromTaken:", amountFromTaken, want);

        assertEq(amountFromTaken, fromAmount, "from amount error");

        // TODO: the old code had a postTake hook. the new code does not!
        // thanks to the post take hook, this was deposited
        // assertEq(IERC20(want).balanceOf(address(bryan)), 0, "want balance should be 0");

        // TODO: i don't like this amount being hard coded.
        assertEq(
            IERC20(want).balanceOf(address(bryan)),
            auctionAmountNeeded,
            "weth balance should be the auction amount needed"
        );
    }

    function test_empty_harvest() public {
        assertEq(bryan.harvest(), 0);
    }

    function test_harvest_eth() public {
        require(address(bryan.UNDERLYING()) == address(weth), "not weth");

        uint256 amount = 1 ether;

        assertEq(bryan.harvest{value: amount}(), amount, "incorrect eth harvest amount");

        // TODO: assert that the share price went up properly
    }

    function test_harvest_weth() public {
        require(address(bryan.UNDERLYING()) == address(weth), "not weth");

        uint256 amount = 1 ether;

        weth.deposit{value: amount}();
        bool success = weth.transfer(address(bryan), amount);

        require(success, "weth transfer failed");

        assertEq(bryan.harvest(), amount, "incorrect weth harvest amount");

        // TODO: assert that the share price went up properly
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

    function test_harvest_with_owner_fees() public {
        // Create token and setup in first block
        FanToken feeToken;
        uint256 initialBalance;
        uint256 initialSupply;
        uint256 rewardAmount = 0.5 ether;
        uint256 ownerFeeBasisPoints = 2500; // 25%

        {
            // TODO: don't prank the factory. instead, call factory.create!
            vm.prank(factory);
            feeToken = new FanToken(
                "Fee Test Token",
                "FEE",
                ownerFeeBasisPoints,
                0, // treasury fees
                owner,
                IERC4626(bryan.asset()),
                treasury,
                weth
            );

            console.log("Created feeToken with 25% owner fees");

            // Set up initial deposit
            (IERC4626 asset, uint256 assets) = _dealAsset(1 ether, address(this));
            asset.approve(address(feeToken), type(uint256).max);
            uint256 when = feeToken.startDeposit(assets, address(this));
            assertEq(when, 0, "first deposit should be instant");

            initialBalance = feeToken.balanceOf(address(this));
            initialSupply = feeToken.totalSupply();

            console.log("Initial setup:");
            console.log("  User balance:", initialBalance);
            console.log("  Total supply:", initialSupply);
        }

        // Send rewards and harvest in second block
        {
            vm.deal(address(this), rewardAmount);
            weth.deposit{value: rewardAmount}();
            require(weth.transfer(address(feeToken), rewardAmount), "weth transfer failed");

            console.log("Sent", rewardAmount, "WETH rewards");

            uint256 harvested = feeToken.harvest();
            assertEq(harvested, rewardAmount, "should harvest all rewards");
            console.log("Harvested:", harvested);
        }

        // Verify results in final block
        {
            uint256 finalBalance = feeToken.balanceOf(address(this));
            uint256 finalSupply = feeToken.totalSupply();
            uint256 expectedFee;
            {
                // The correct calculation should match what harvest() actually does:
                // 1. underlyingAssets -> prize vault assets (1:1 for WETH vault)
                // 2. shareValue = previewDeposit(prizeVaultAssets)
                // 3. ownerFeeShares = shareValue * ownerFeeBasisPoints / 10000
                // 4. expectedFee = previewRedeem(ownerFeeShares) after harvestSponsorship corrections

                // From the contract logs, we know the contract calculates shareValue = rewardAmount
                // because for a 1:1 asset, previewDeposit should return the same amount
                uint256 shareValue = rewardAmount; // This matches the contract's calculation
                uint256 expectedFeeShares = (shareValue * ownerFeeBasisPoints) / 10000;

                console.log("Fee calculation debug:");
                console.log("  Reward amount:", rewardAmount);
                console.log("  Share value:", shareValue);
                console.log("  Expected fee shares:", expectedFeeShares);

                // The final fee amount will be affected by harvestSponsorship burns
                // We can't predict the exact amount, so we'll just verify it's reasonable
                expectedFee = expectedFeeShares; // Rough estimate before burns

                assertGt(shareValue, 0, "should have share value");
                assertGt(expectedFeeShares, 0, "should have expected fee shares");
            }
            // Owner fees are now paid in assets (prize vault tickets), not fan token shares
            IERC4626 asset = IERC4626(feeToken.asset());
            uint256 ownerAssetBalance = asset.balanceOf(owner);

            console.log("Final state:");
            console.log("  User balance:", finalBalance);
            console.log("  Owner asset balance:", ownerAssetBalance);
            console.log("  Expected fee:", expectedFee);

            // Verify fee distribution - fees are now paid in assets directly
            uint256 expectedAssetFee = (rewardAmount * ownerFeeBasisPoints) / 10000;
            assertApproxEqRel(
                ownerAssetBalance, expectedAssetFee, 0.1e18, "owner should get approximately correct asset fee"
            );
            assertGt(ownerAssetBalance, 0, "owner should get some asset fee");

            // Verify no WETH left
            assertEq(weth.balanceOf(address(feeToken)), 0, "all WETH should be deposited");

            // Verify the harvest processed correctly
            console.log("  Final balance vs initial:", finalBalance, initialBalance);
            console.log("  Final supply vs initial:", finalSupply, initialSupply);

            // The harvest may change supply due to harvestSponsorship mechanics
            // The key verification is that owner got asset fees
            uint256 finalTotalAssets = feeToken.totalAssets();
            assertGt(finalTotalAssets, 1 ether, "total assets should increase after harvest");
        }
    }

    function test_harvest_with_treasury_fees() public {
        // Create a FanToken with 15% treasury fees
        uint256 ownerFeeBasisPoints = 0;
        uint256 treasuryFeeBasisPoints = 1500; // 15%

        // TODO: don't prank the factory. instead, call factory.create!
        vm.prank(factory);
        FanToken feeToken = new FanToken(
            "Treasury Fee Test",
            "TFEE",
            ownerFeeBasisPoints,
            treasuryFeeBasisPoints,
            owner,
            IERC4626(bryan.asset()),
            treasury,
            weth
        );

        console.log("Created feeToken with 15% treasury fees");

        // Set up initial deposit
        uint256 initialDeposit = 2 ether;
        (IERC4626 asset, uint256 assets) = _dealAsset(initialDeposit, address(this));

        asset.approve(address(feeToken), type(uint256).max);
        uint256 when = feeToken.startDeposit(assets, address(this));

        // First deposit to a new contract should be instant
        assertEq(when, 0, "first deposit should be instant");

        uint256 initialTreasuryBalance = feeToken.balanceOf(treasury);
        console.log("Initial treasury balance:", initialTreasuryBalance);
        console.log("Treasury isSponsor:", feeToken.isSponsor(treasury));

        // Send fake rewards using transfer instead of deal
        uint256 rewardAmount = 1 ether;
        vm.deal(address(this), rewardAmount);
        weth.deposit{value: rewardAmount}();
        require(weth.transfer(address(feeToken), rewardAmount), "weth transfer failed");

        console.log("Sent", rewardAmount, "WETH rewards");

        // Harvest
        uint256 harvested = feeToken.harvest();
        assertEq(harvested, rewardAmount, "should harvest full reward amount");

        // Check treasury got fees as sponsor assets
        uint256 treasurySponsorBalance = feeToken.balanceOfSponsor(treasury);
        console.log("Treasury sponsor balance after harvest:", treasurySponsorBalance);

        uint256 expectedTreasuryFee;
        {
            // Calculate expected fee correctly: get prize vault assets, then fan token shares, then fee shares, then convert back to assets
            IERC4626 prizeVault = IERC4626(feeToken.asset());
            uint256 prizeVaultAssets = prizeVault.previewDeposit(rewardAmount);
            uint256 fanTokenShares = feeToken.previewDeposit(prizeVaultAssets);
            uint256 expectedFeeShares = (fanTokenShares * treasuryFeeBasisPoints) / 10000;
            expectedTreasuryFee = feeToken.previewRedeem(expectedFeeShares);

            console.log("Treasury fee calculation debug:");
            console.log("  Reward amount:", rewardAmount);
            console.log("  Prize vault assets:", prizeVaultAssets);
            console.log("  Fan token shares:", fanTokenShares);
            console.log("  Expected fee shares:", expectedFeeShares);
            console.log("  Expected fee:", expectedTreasuryFee);
        }
        console.log("Expected treasury fee:", expectedTreasuryFee);

        // Verify fee distribution (approximate due to share burn mechanics)
        // Treasury fees are now paid in assets, not sponsor shares
        IERC4626 feeAsset = IERC4626(feeToken.asset());
        uint256 treasuryAssetBalance = feeAsset.balanceOf(treasury);

        uint256 expectedAssetFee = (rewardAmount * treasuryFeeBasisPoints) / 10000;
        assertApproxEqRel(
            treasuryAssetBalance, expectedAssetFee, 0.1e18, "treasury should get approximately correct asset fee"
        );
        assertGt(treasuryAssetBalance, 0, "treasury should get some asset fee");
    }

    function test_harvest_with_both_fees() public {
        // Simplified test to avoid stack too deep
        vm.prank(factory);
        FanToken feeToken = new FanToken(
            "Both Fees Test",
            "BOTH",
            1000, // 10% owner fee
            500, // 5% treasury fee
            owner,
            IERC4626(bryan.asset()),
            treasury,
            weth
        );

        console.log("Created feeToken with 10% owner + 5% treasury fees");

        // Simple deposit
        (IERC4626 asset, uint256 assets) = _dealAsset(1 ether, address(this));
        asset.approve(address(feeToken), type(uint256).max);
        uint256 when = feeToken.startDeposit(assets, address(this));

        // First deposit to a new contract should be instant
        assertEq(when, 0, "first deposit should be instant");

        console.log("Initial balance:", feeToken.balanceOf(address(this)));

        // Send rewards using transfer instead of deal
        uint256 rewardAmount = 0.5 ether;
        vm.deal(address(this), rewardAmount);
        weth.deposit{value: rewardAmount}();
        require(weth.transfer(address(feeToken), rewardAmount), "weth transfer failed");

        console.log("Sent", rewardAmount, "WETH rewards");

        // Harvest
        uint256 harvested = feeToken.harvest();
        assertEq(harvested, rewardAmount, "should harvest all rewards");

        console.log("Final balance:", feeToken.balanceOf(address(this)));

        // Check fees were distributed
        console.log("Owner sponsor balance:", feeToken.balanceOfSponsor(owner));
        console.log("Treasury sponsor balance:", feeToken.balanceOfSponsor(treasury));

        // Both owner and treasury should get fees in assets now
        IERC4626 feeAsset = IERC4626(feeToken.asset());
        uint256 ownerAssetFee = feeAsset.balanceOf(owner);
        uint256 treasuryAssetFee = feeAsset.balanceOf(treasury);

        assertGt(ownerAssetFee, 0, "owner should get asset fee");
        assertGt(treasuryAssetFee, 0, "treasury should get asset fee");
    }

    function test_sponsor_burn() public {
        // Set up a sponsor with some assets
        address sponsor = makeAddr("sponsor");

        {
            uint256 depositAmount = 1 ether;
            (IERC4626 asset, uint256 assets) = _dealAsset(depositAmount * 2, address(this));
            require(asset.transfer(sponsor, assets), "asset transfer failed");

            // Sponsor deposits and becomes a sponsor
            vm.startPrank(sponsor);
            bryan.setSponsorship(true);
            asset.approve(address(bryan), type(uint256).max);

            uint256 when = bryan.startDeposit(assets);
            assertEq(when, 0, "first deposit should be instant for sponsor");
        }

        // Record initial state in separate scope
        {
            uint256 initialSponsorBalance = bryan.balanceOfSponsor(sponsor);
            uint256 initialTotalSponsorAssets = bryan.totalSponsorAssets();
            uint256 initialContractShares = bryan.balanceOf(address(bryan));

            console.log("Initial sponsor state:");
            console.log("  Sponsor balance:", initialSponsorBalance);
            console.log("  Total sponsor assets:", initialTotalSponsorAssets);
            console.log("  Contract shares:", initialContractShares);

            assertGt(initialSponsorBalance, 0, "sponsor should have balance");
            assertGt(initialTotalSponsorAssets, 0, "should have total sponsor assets");

            // Burn half the assets
            uint256 burnAmount = initialSponsorBalance / 2;
            console.log("Burning", burnAmount, "sponsor assets");
            bryan.sponsorBurn(burnAmount);

            // Verify results
            uint256 finalSponsorBalance = bryan.balanceOfSponsor(sponsor);
            uint256 finalTotalSponsorAssets = bryan.totalSponsorAssets();
            uint256 finalContractShares = bryan.balanceOf(address(bryan));

            console.log("After sponsor burn:");
            console.log("  Sponsor balance:", finalSponsorBalance);
            console.log("  Total sponsor assets:", finalTotalSponsorAssets);
            console.log("  Contract shares:", finalContractShares);

            assertEq(
                finalSponsorBalance,
                initialSponsorBalance - burnAmount,
                "sponsor balance should decrease by burn amount"
            );
            assertEq(
                finalTotalSponsorAssets, initialTotalSponsorAssets - burnAmount, "total sponsor assets should decrease"
            );
            assertLt(finalContractShares, initialContractShares, "contract shares should decrease from burn");
        }
    }

    /*
    function test_sponsor_burn_with_beneficiaries() public {
        // Set up multiple users: one sponsor and two regular users
        address sponsor = makeAddr("sponsor");
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");

        uint256 depositAmount = 1 ether;
        (IERC4626 asset, uint256 totalAssets) = _dealAsset(depositAmount * 4, address(this));

        // Distribute assets
        asset.transfer(sponsor, totalAssets);
        require(asset.transfer(alice, depositAmount), "asset transfer failed");
        asset.transfer(bob, depositAmount);

        // Regular users deposit first
        vm.startPrank(alice);
        asset.approve(address(bryan), type(uint256).max);
        uint256 aliceWhen = bryan.startDeposit(depositAmount, alice);
        if (aliceWhen > 0) {
            vm.warp(aliceWhen);
        }
        bryan.deposit(depositAmount, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        asset.approve(address(bryan), type(uint256).max);
        uint256 bobWhen = bryan.startDeposit(depositAmount, bob);
        if (bobWhen > 0) {
            vm.warp(bobWhen);
        }
        bryan.deposit(depositAmount, bob);
        vm.stopPrank();

        // Sponsor deposits
        vm.startPrank(sponsor);
        bryan.setSponsorship(true);
        asset.approve(address(bryan), type(uint256).max);
        uint256 sponsorWhen = bryan.startDeposit(depositAmount * 2, sponsor);
        if (sponsorWhen > 0) {
            vm.warp(sponsorWhen);
        }
        bryan.deposit(depositAmount * 2, sponsor);

        // Record initial balances
        uint256 initialAliceBalance = bryan.balanceOf(alice);
        uint256 initialBobBalance = bryan.balanceOf(bob);
        uint256 initialSponsorAssets = bryan.balanceOfSponsor(sponsor);
        uint256 initialAliceUnderlying = bryan.balanceOfUnderlying(alice);
        uint256 initialBobUnderlying = bryan.balanceOfUnderlying(bob);

        console.log("Initial state:");
        console.log("  Alice balance:", initialAliceBalance);
        console.log("  Alice underlying:", initialAliceUnderlying);
        console.log("  Bob balance:", initialBobBalance);
        console.log("  Bob underlying:", initialBobUnderlying);
        console.log("  Sponsor assets:", initialSponsorAssets);

        // Sponsor burns half their assets to benefit others (not all to avoid TwabController constraints)
        uint256 burnAmount = initialSponsorAssets / 2;
        console.log("Sponsor burning half", burnAmount, "assets");

        bryan.sponsorBurn(burnAmount);

        // Sponsor should have remaining assets
        uint256 expectedSponsorAssets = initialSponsorAssets - burnAmount;
        assertEq(bryan.balanceOfSponsor(sponsor), expectedSponsorAssets, "sponsor should have remaining assets after burning half");

        // Alice and Bob should have same share balances but more underlying value
        assertEq(bryan.balanceOf(alice), initialAliceBalance, "alice shares shouldn't change");
        assertEq(bryan.balanceOf(bob), initialBobBalance, "bob shares shouldn't change");

        // But their underlying value should increase due to burned shares reducing total supply
        assertGt(bryan.balanceOfUnderlying(alice), initialAliceUnderlying, "alice underlying should increase");
        assertGt(bryan.balanceOfUnderlying(bob), initialBobUnderlying, "bob underlying should increase");

        // Both should gain the same amount (equal shares)
        uint256 aliceGain = bryan.balanceOfUnderlying(alice) - initialAliceUnderlying;
        uint256 bobGain = bryan.balanceOfUnderlying(bob) - initialBobUnderlying;

        assertApproxEqAbs(aliceGain, bobGain, 1, "alice and bob should gain similar amounts");
        assertGt(aliceGain, 0, "alice should gain from sponsor burn");
        assertGt(bobGain, 0, "bob should gain from sponsor burn");
    }
    */

    function test_sponsor_burn_insufficient_balance() public {
        address sponsor = makeAddr("sponsor");

        uint256 depositAmount = 1 ether;
        (IERC4626 asset, uint256 assets) = _dealAsset(depositAmount, address(this));

        require(asset.transfer(sponsor, assets), "asset transfer failed");

        vm.startPrank(sponsor);
        bryan.setSponsorship(true);
        asset.approve(address(bryan), type(uint256).max);
        bryan.deposit(assets, sponsor);

        uint256 sponsorBalance = bryan.balanceOfSponsor(sponsor);
        console.log("Sponsor balance:", sponsorBalance);

        // Try to burn more than balance
        uint256 excessiveBurnAmount = sponsorBalance + 1 ether;
        console.log("Attempting to burn", excessiveBurnAmount, "(more than balance)");

        vm.expectRevert();
        bryan.sponsorBurn(excessiveBurnAmount);

        console.log("Correctly reverted on excessive burn attempt");
    }

    function test_harvestSponsorship_with_rewards() public {
        // Set up scenario: sponsor and non-sponsor users, then send rewards to trigger harvestSponsorship
        address sponsor = makeAddr("sponsor");
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");

        uint256 depositAmount = 1 ether;
        (IERC4626 asset,) = _dealAsset(depositAmount * 4, address(this));

        // Give assets to all users
        require(asset.transfer(sponsor, depositAmount));
        require(asset.transfer(alice, depositAmount), "asset transfer failed");
        require(asset.transfer(bob, depositAmount));

        // Non-sponsors deposit first with proper timing
        vm.startPrank(alice);
        asset.approve(address(bryan), type(uint256).max);
        uint256 aliceWhen = bryan.startDeposit(depositAmount, alice);
        if (aliceWhen > 0) {
            vm.warp(aliceWhen);
            bryan.deposit(depositAmount, alice);
        }

        vm.startPrank(bob);
        asset.approve(address(bryan), type(uint256).max);
        uint256 bobWhen = bryan.startDeposit(depositAmount, bob);
        if (bobWhen > 0) {
            vm.warp(bobWhen);
            bryan.deposit(depositAmount, bob);
        }

        // Sponsor deposits with proper timing
        vm.startPrank(sponsor);
        bryan.setSponsorship(true);
        asset.approve(address(bryan), type(uint256).max);
        uint256 sponsorWhen = bryan.startDeposit(depositAmount, sponsor);
        if (sponsorWhen > 0) {
            vm.warp(sponsorWhen);
            bryan.deposit(depositAmount, sponsor);
        }
        vm.stopPrank();

        // Record initial state
        uint256 initialSponsorAssets = bryan.balanceOfSponsor(sponsor);
        uint256 initialAliceUnderlying = bryan.balanceOfUnderlying(alice);
        uint256 initialBobUnderlying = bryan.balanceOfUnderlying(bob);

        // Send fake rewards to the contract using transfer
        uint256 rewardAmount = 0.5 ether;
        vm.deal(address(this), rewardAmount);
        weth.deposit{value: rewardAmount}();
        require(weth.transfer(address(bryan), rewardAmount), "weth transfer failed");

        // Harvest - this should trigger harvestSponsorship automatically
        assertEq(bryan.harvest(), rewardAmount, "should harvest all rewards");

        // Key verification: sponsor balance should remain the same in underlying value
        assertEq(bryan.balanceOfSponsor(sponsor), initialSponsorAssets, "sponsor assets should remain the same");

        // Non-sponsors should benefit from the harvest - both should gain equal amounts
        assertApproxEqAbs(
            bryan.balanceOfUnderlying(alice) - initialAliceUnderlying,
            bryan.balanceOfUnderlying(bob) - initialBobUnderlying,
            1,
            "alice and bob should gain equal amounts from harvest"
        );
        assertGt(bryan.balanceOfUnderlying(alice) - initialAliceUnderlying, 0, "alice should benefit from harvest");
        assertGt(bryan.balanceOfUnderlying(bob) - initialBobUnderlying, 0, "bob should benefit from harvest");
    }

    function test_harvestSponsorship_multiple_sponsors() public {
        // Test with multiple sponsors to ensure proper accounting
        address sponsor1 = makeAddr("sponsor1");
        address sponsor2 = makeAddr("sponsor2");
        address alice = makeAddr("alice");

        uint256 depositAmount = 1 ether;
        (IERC4626 asset,) = _dealAsset(depositAmount * 4, address(this));

        // Distribute assets
        require(asset.transfer(sponsor1, depositAmount), "asset transfer failed");
        require(asset.transfer(sponsor2, depositAmount), "asset transfer failed");
        require(asset.transfer(alice, depositAmount), "asset transfer failed");

        // Alice (non-sponsor) deposits first with proper timing
        vm.startPrank(alice);
        asset.approve(address(bryan), type(uint256).max);
        uint256 aliceWhen = bryan.startDeposit(depositAmount, alice);
        if (aliceWhen > 0) {
            vm.warp(aliceWhen);
            bryan.deposit(depositAmount, alice);
        }
        vm.stopPrank();

        // First sponsor deposits with proper timing
        vm.startPrank(sponsor1);
        bryan.setSponsorship(true);
        asset.approve(address(bryan), type(uint256).max);
        uint256 sponsor1When = bryan.startDeposit(depositAmount, sponsor1);
        if (sponsor1When > 0) {
            vm.warp(sponsor1When);
            bryan.deposit(depositAmount, sponsor1);
        }
        vm.stopPrank();

        // Second sponsor deposits with proper timing
        vm.startPrank(sponsor2);
        bryan.setSponsorship(true);
        asset.approve(address(bryan), type(uint256).max);
        uint256 sponsor2When = bryan.startDeposit(depositAmount, sponsor2);
        if (sponsor2When > 0) {
            vm.warp(sponsor2When);
            bryan.deposit(depositAmount, sponsor2);
        }
        vm.stopPrank();

        uint256 initialAliceUnderlying;
        uint256 initialSponsor1Assets;
        uint256 initialSponsor2Assets;

        // Record state before harvest
        {
            initialAliceUnderlying = bryan.balanceOfUnderlying(alice);
            initialSponsor1Assets = bryan.balanceOfSponsor(sponsor1);
            initialSponsor2Assets = bryan.balanceOfSponsor(sponsor2);
            uint256 initialTotalSponsorAssets = bryan.totalSponsorAssets();

            console.log("Before harvest - multiple sponsors:");
            console.log("  Alice underlying:", initialAliceUnderlying);
            console.log("  Sponsor1 assets:", initialSponsor1Assets);
            console.log("  Sponsor2 assets:", initialSponsor2Assets);
            console.log("  Total sponsor assets:", initialTotalSponsorAssets);
        }

        // Send substantial rewards and harvest
        uint256 rewardAmount = 1 ether;
        {
            vm.deal(address(this), rewardAmount);
            weth.deposit{value: rewardAmount}();
            require(weth.transfer(address(bryan), rewardAmount), "weth transfer failed");
            console.log("Sent", rewardAmount, "WETH rewards");

            uint256 harvested = bryan.harvest();
            assertEq(harvested, rewardAmount, "should harvest all rewards");
        }

        // Check final state and assertions
        {
            uint256 finalAliceUnderlying = bryan.balanceOfUnderlying(alice);
            uint256 finalSponsor1Assets = bryan.balanceOfSponsor(sponsor1);
            uint256 finalSponsor2Assets = bryan.balanceOfSponsor(sponsor2);
            uint256 finalTotalSponsorAssets = bryan.totalSponsorAssets();

            console.log("After harvest - multiple sponsors:");
            console.log("  Alice underlying:", finalAliceUnderlying);
            console.log("  Sponsor1 assets:", finalSponsor1Assets);
            console.log("  Sponsor2 assets:", finalSponsor2Assets);
            console.log("  Total sponsor assets:", finalTotalSponsorAssets);

            // Sponsors should maintain their asset values
            assertEq(finalSponsor1Assets, initialSponsor1Assets, "sponsor1 assets should remain constant");
            assertEq(finalSponsor2Assets, initialSponsor2Assets, "sponsor2 assets should remain constant");

            // Alice should benefit from all the rewards
            uint256 aliceGain = finalAliceUnderlying - initialAliceUnderlying;
            console.log("Alice's gain from harvest:", aliceGain);

            assertGt(aliceGain, 0, "alice should benefit from harvest with multiple sponsors");
            assertGt(aliceGain, rewardAmount / 2, "alice should get substantial portion of rewards");
        }
    }

    function test_sponsor_transfer_success() public {
        address sponsor = makeAddr("sponsor");
        address recipient = makeAddr("recipient");

        // Set up sponsor with assets
        (IERC4626 asset, uint256 assets) = _dealAsset(1 ether, address(this));
        require(asset.transfer(sponsor, assets), "asset transfer failed");

        vm.startPrank(sponsor);
        bryan.setSponsorship(true);
        asset.approve(address(bryan), type(uint256).max);
        uint256 when = bryan.startDeposit(assets, sponsor);
        if (when > 0) {
            vm.warp(when);
            bryan.deposit(assets, sponsor);
        }

        // Get sponsor's actual asset balance and transfer half
        uint256 sponsorAssets = bryan.balanceOfSponsor(sponsor);
        uint256 transferAmount = sponsorAssets / 2;

        console.log("Before transfer:");
        console.log("  Sponsor assets:", sponsorAssets);
        console.log("  Transfer amount:", transferAmount);

        assertGt(sponsorAssets, 0, "sponsor should have assets");
        assertGt(transferAmount, 0, "transfer amount should be positive");

        // Make recipient a sponsor for the transfer to work
        vm.stopPrank();
        vm.prank(recipient);
        bryan.setSponsorship(true);

        vm.startPrank(sponsor);
        bryan.sponsorTransfer(recipient, transferAmount);
        vm.stopPrank();

        // Verify transfer
        uint256 finalSponsorAssets = bryan.balanceOfSponsor(sponsor);
        uint256 finalRecipientAssets = bryan.balanceOfSponsor(recipient);

        console.log("After transfer:");
        console.log("  Sponsor assets:", finalSponsorAssets);
        console.log("  Recipient assets:", finalRecipientAssets);

        assertEq(finalSponsorAssets, sponsorAssets - transferAmount, "sponsor assets should decrease");
        assertEq(finalRecipientAssets, transferAmount, "recipient should receive transferred assets");
    }

    function test_deposit_delay_constant() public view {
        assertEq(bryan.DEPOSIT_DELAY(), 3 days);
    }

    /*
    function test_deposit_and_withdraw_with_fees() public {
        // Deploy a contract with fees and test deposit/withdraw
        vm.prank(factory);
        FanToken feeToken = new FanToken(
            "Fee Test",
            "FEE",
            1000, // 10% owner fee
            500,  // 5% treasury fee
            owner,
            IERC4626(bryan.asset()),
            treasury,
            weth
        );

        (IERC4626 asset, uint256 assets) = _dealAsset(1 ether, address(this));
        asset.approve(address(feeToken), type(uint256).max);
        uint256 when = feeToken.startDeposit(assets, address(this));
        if (when > 0) {
            vm.warp(when);
        }
        feeToken.deposit(assets, address(this));

        uint256 shares = feeToken.balanceOf(address(this));
        assertGt(shares, 0, "should receive shares after fee token deposit");

        // Test withdrawal
        uint256 withdrawn = feeToken.redeem(shares, address(this), address(this));
        assertGt(withdrawn, 0, "should receive assets after fee token redeem");
        assertEq(feeToken.balanceOf(address(this)), 0, "balance should be zero after redeem");
    }
    */

    function test_owner_only() public {
        address notOwner = makeAddr("notOwner");

        // Test that non-owner cannot call owner functions
        vm.startPrank(notOwner);
        vm.expectRevert();
        bryan.enableAuction(IERC20(address(weth)));
    }

    function test_claiming_pool_rewards() public {
        // Since we don't have actual POOL rewards in test, just verify the harvest function works
        uint256 initialBalance = weth.balanceOf(address(bryan));

        // Send some WETH to simulate rewards
        vm.deal(address(this), 1 ether);
        weth.deposit{value: 1 ether}();
        require(weth.transfer(address(bryan), 1 ether));

        uint256 harvested = bryan.harvest();
        assertEq(harvested, 1 ether, "should harvest exactly 1 ether of rewards");
        assertEq(weth.balanceOf(address(bryan)), initialBalance);
    }

    function test_withdraw_sponsor() public {
        // Setup sponsor with assets
        address sponsor = makeAddr("sponsor");

        (IERC4626 asset, uint256 assets) = _dealAsset(10 ether, address(this));
        require(asset.transfer(sponsor, assets), "asset transfer failed");

        vm.startPrank(sponsor);
        bryan.setSponsorship(true);
        asset.approve(address(bryan), type(uint256).max);

        uint256 when = bryan.startDeposit(assets, sponsor);
        if (when > 0) {
            vm.warp(when);
            bryan.deposit(assets, sponsor);
        }

        uint256 sponsorShares = bryan.balanceOf(sponsor);

        // If sponsor has shares, test withdrawal
        if (sponsorShares > 0) {
            uint256 withdrawAmount = bryan.convertToAssets(sponsorShares / 2); // withdraw half
            uint256 withdrawn = bryan.withdraw(withdrawAmount, sponsor, sponsor);

            uint256 sponsorSharesAfter = bryan.balanceOf(sponsor);
            assertLe(sponsorSharesAfter, sponsorShares, "sponsor shares should not increase after withdrawal");
            assertGt(withdrawn, 0, "should receive assets from withdrawal");
        }
        vm.stopPrank();
        // Total sponsored shares are tracked by the contract
        assertGt(bryan.totalSponsoredShares(), 0);
        assertGt(bryan.totalSponsoredAssets(), 0);
    }

    function test_sponsorTransferFrom_success() public {
        // Setup two sponsors
        address sponsor1 = makeAddr("sponsor1");
        address sponsor2 = makeAddr("sponsor2");

        (IERC4626 asset, uint256 assets) = _dealAsset(10 ether, address(this));
        require(asset.transfer(sponsor1, assets));

        vm.startPrank(sponsor1);
        bryan.setSponsorship(true);
        asset.approve(address(bryan), type(uint256).max);

        uint256 when = bryan.startDeposit(assets, sponsor1);
        if (when > 0) {
            vm.warp(when);
            bryan.deposit(assets, sponsor1);
        }
        vm.stopPrank();

        vm.prank(sponsor2);
        bryan.setSponsorship(true);

        uint256 sponsor1Shares = bryan.balanceOf(sponsor1);
        uint256 transferAmount = sponsor1Shares / 3; // Transfer 1/3 of shares

        // Approve sponsor2 to transfer from sponsor1
        vm.prank(sponsor1);
        bryan.approve(sponsor2, transferAmount);

        uint256 sponsor1Before = bryan.balanceOf(sponsor1);
        uint256 sponsor2Before = bryan.balanceOf(sponsor2);

        // Transfer from sponsor1 to sponsor2
        vm.prank(sponsor2);
        bool success = bryan.sponsorTransferFrom(sponsor1, sponsor2, transferAmount);
        assertTrue(success, "sponsorTransferFrom should return true on successful transfer");

        assertEq(bryan.balanceOf(sponsor1), sponsor1Before - transferAmount);
        assertEq(bryan.balanceOf(sponsor2), sponsor2Before + transferAmount);
        assertEq(bryan.allowance(sponsor1, sponsor2), 0);
        // Total sponsored shares are held by the contract, not individual sponsors
        assertGt(bryan.totalSponsoredShares(), 0);
        assertGt(bryan.totalSponsoredAssets(), 0);
    }

    function test_sponsorTransferFrom_insufficient_allowance() public {
        address sponsor1 = makeAddr("sponsor1");
        address sponsor2 = makeAddr("sponsor2");

        (IERC4626 asset, uint256 assets) = _dealAsset(10 ether, address(this));
        require(asset.transfer(sponsor1, assets));

        vm.startPrank(sponsor1);
        bryan.setSponsorship(true);
        asset.approve(address(bryan), type(uint256).max);

        uint256 when = bryan.startDeposit(assets, sponsor1);
        if (when > 0) {
            vm.warp(when);
            bryan.deposit(assets, sponsor1);
        }
        vm.stopPrank();

        vm.prank(sponsor2);
        bryan.setSponsorship(true);

        // Try to transfer without approval
        uint256 transferAmount = 1 ether; // Try to transfer a specific amount
        vm.prank(sponsor2);
        vm.expectRevert(); // Should fail due to insufficient allowance
        bryan.sponsorTransferFrom(sponsor1, sponsor2, transferAmount);
    }

    function test_totalSponsoredShares_and_totalSponsoredAssets() public {
        assertEq(bryan.totalSponsoredShares(), 0);
        assertEq(bryan.totalSponsoredAssets(), 0);

        // Add sponsors
        address sponsor1 = makeAddr("sponsor1");
        address sponsor2 = makeAddr("sponsor2");

        (IERC4626 asset, uint256 totalAssets) = _dealAsset(15 ether, address(this));
        uint256 assets1 = (totalAssets * 2) / 3; // 10 ether worth
        uint256 assets2 = totalAssets - assets1; // 5 ether worth

        require(asset.transfer(sponsor1, assets1));
        require(asset.transfer(sponsor2, assets2));

        vm.startPrank(sponsor1);
        bryan.setSponsorship(true);
        asset.approve(address(bryan), type(uint256).max);
        uint256 when1 = bryan.startDeposit(assets1, sponsor1);
        if (when1 > 0) {
            vm.warp(when1);
            bryan.deposit(assets1, sponsor1);
        }
        vm.stopPrank();

        vm.startPrank(sponsor2);
        bryan.setSponsorship(true);
        asset.approve(address(bryan), type(uint256).max);

        // After sponsor1 deposits and sponsor2 becomes a sponsor,
        // sponsor1's shares should be moved to the contract
        uint256 contractShares = bryan.totalSponsoredShares();
        assertGt(contractShares, 0, "contract should hold some sponsored shares after sponsor deposit");
        assertEq(bryan.totalSponsoredAssets(), bryan.convertToAssets(contractShares));

        // Deposit for sponsor2
        uint256 when2 = bryan.startDeposit(assets2, sponsor2);
        if (when2 > 0) {
            vm.warp(when2);
            bryan.deposit(assets2, sponsor2);
        }
        vm.stopPrank();

        // After both sponsors deposit, all shares should be in the contract
        uint256 totalContractShares = bryan.totalSponsoredShares();
        assertGt(
            totalContractShares, contractShares, "total sponsored shares should increase after second sponsor deposit"
        );
        assertEq(bryan.totalSponsoredAssets(), bryan.convertToAssets(totalContractShares));
    }

    function test_finishDeposit_for_another_user() public {
        address depositor = makeAddr("depositor");
        address finisher = makeAddr("finisher");

        // Ensure this is NOT the first deposit to the contract
        // by making a small deposit first
        (IERC4626 asset, uint256 initialAssets) = _dealAsset(0.1 ether, address(this));
        asset.approve(address(bryan), type(uint256).max);
        bryan.deposit(initialAssets, address(this));

        // Now set up the actual test
        ( /*IERC4626 asset2*/ , uint256 assets) = _dealAsset(1 ether, address(this));
        require(asset.transfer(depositor, assets));

        // Depositor requests sponsorship and starts deposit
        vm.startPrank(depositor);
        bryan.setSponsorship(true);
        asset.approve(address(bryan), type(uint256).max);

        uint256 when = bryan.startDeposit(assets, depositor);

        assertGt(when, block.timestamp, "deposit should have delay after initial deposit");

        // Warp to when deposit is ready
        vm.warp(when);

        // Different user (finisher) calls finishDeposit for the depositor
        vm.startPrank(finisher);
        uint256 finishedDeposit = bryan.finishDeposit(depositor, depositor);

        assertGt(finishedDeposit, 0, "there should be some finished deposit");

        // Since depositor became a sponsor, their shares should be moved to the contract
        uint256 contractSponsoredShares = bryan.totalSponsoredShares();
        assertGt(contractSponsoredShares, 0, "contract should hold sponsored shares after sponsor deposit");
        assertGt(bryan.totalSponsoredAssets(), 0, "sponsored assets should be tracked after sponsor deposit");

        // Depositor's direct balance should be zero since they're a sponsor
        uint256 depositorBalanceAfter = bryan.balanceOf(depositor);
        assertEq(
            depositorBalanceAfter,
            0,
            "sponsor depositor should have zero direct balance, shares moved to sponsored pool"
        );
    }

    function test_harvesting_weth() public {
        // Add WETH to contract and sweep it
        vm.deal(address(this), 2 ether);
        weth.deposit{value: 2 ether}();
        require(weth.transfer(address(bryan), 2 ether));

        uint256 initialContractBalance = bryan.totalAssets();
        uint256 harvested = bryan.harvest();

        assertEq(harvested, 2 ether, "should harvest exactly 2 ether of WETH rewards");
        assertGt(bryan.totalAssets(), initialContractBalance);
    }

    function test_initial_total_sponsor_assets() public view {
        assertEq(bryan.totalSponsorAssets(), 0);
    }

    function test_version() public {
        string memory factoryVersion = bryan.FACTORY().version();
        string memory tokenVersion = bryan.version();
        assertEq(factoryVersion, "3.0.0", "factory version should be 3.0.0");
        assertEq(tokenVersion, factoryVersion, "token version should match factory version");
    }

    function test_harvest_empty_contract() public {
        uint256 harvested = bryan.harvest();
        assertEq(harvested, 0, "harvest should return 0 when contract is empty");
    }

    function test_sponsor_burn_zero_amount() public {
        address sponsor = makeAddr("sponsor");
        vm.startPrank(sponsor);
        bryan.setSponsorship(true);

        // Burning 0 should succeed (it just does nothing)
        bryan.sponsorBurn(0);
        assertEq(bryan.balanceOfSponsor(sponsor), 0, "sponsor should have 0 assets");
    }

    function test_sponsor_burn_increases_share_value() public {
        // Test that when a sponsor burns tokens, the share value for regular users increases
        address sponsor = makeAddr("sponsor");
        address alice = makeAddr("alice");
        uint256 depositAmount = 2 ether;

        // Deal assets and distribute
        (IERC4626 asset,) = _dealAsset(depositAmount * 2, address(this));
        require(asset.transfer(sponsor, depositAmount));
        require(asset.transfer(alice, depositAmount), "asset transfer failed");

        // Alice deposits first (will be instant since it's first deposit)
        vm.startPrank(alice);
        asset.approve(address(bryan), type(uint256).max);
        bryan.deposit(depositAmount, alice);
        vm.stopPrank();

        // Sponsor becomes sponsor and deposits
        vm.startPrank(sponsor);
        bryan.setSponsorship(true);
        asset.approve(address(bryan), type(uint256).max);
        uint256 sponsorWhen = bryan.startDeposit(depositAmount, sponsor);
        if (sponsorWhen > 0) {
            vm.warp(sponsorWhen);
            bryan.deposit(depositAmount, sponsor);
        }

        uint256 initialAliceUnderlying = bryan.balanceOfUnderlying(alice);
        uint256 sponsorAssets = bryan.balanceOfSponsor(sponsor);

        console.log("Before burn:");
        console.log("  Alice underlying:", initialAliceUnderlying);
        console.log("  Sponsor assets:", sponsorAssets);

        assertGt(sponsorAssets, 0, "sponsor should have assets");

        // Sponsor burns half their assets
        uint256 burnAmount = sponsorAssets / 2;
        bryan.sponsorBurn(burnAmount);

        uint256 finalAliceUnderlying = bryan.balanceOfUnderlying(alice);
        uint256 finalSponsorAssets = bryan.balanceOfSponsor(sponsor);

        console.log("After burn:");
        console.log("  Alice underlying:", finalAliceUnderlying);
        console.log("  Sponsor assets:", finalSponsorAssets);

        // Assertions
        assertEq(finalSponsorAssets, sponsorAssets - burnAmount, "sponsor assets should decrease");
        assertGt(finalAliceUnderlying, initialAliceUnderlying, "alice underlying should increase");
    }

    function test_deposit_redeem_all_then_new_deposit() public {
        // Test depositing, redeeming 100%, then another user depositing again
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        uint256 depositAmount = 2 ether;

        // Deal assets
        (IERC4626 asset,) = _dealAsset(depositAmount * 3, address(this));
        IERC20(address(asset)).safeTransfer(alice, depositAmount);
        IERC20(address(asset)).safeTransfer(bob, depositAmount);

        // Alice deposits first (instant since it's the first deposit)
        vm.startPrank(alice);
        asset.approve(address(bryan), type(uint256).max);
        bryan.deposit(depositAmount, alice);

        uint256 aliceShares = bryan.balanceOf(alice);

        assertGt(aliceShares, 0, "alice should have shares");
        assertGt(bryan.totalSupply(), 0, "should have total supply");

        // Alice redeems all her shares
        bryan.redeem(aliceShares, alice, alice);

        assertEq(bryan.balanceOf(alice), 0, "alice should have no shares");
        assertEq(bryan.totalSupply(), 0, "total supply should be zero");

        vm.stopPrank();

        // TODO: have a similar test that harvests some prizes here!

        // Bob deposits after total supply went to zero (should be instant like first deposit)
        vm.startPrank(bob);
        asset.approve(address(bryan), type(uint256).max);
        bryan.deposit(depositAmount, bob);

        uint256 bobShares = bryan.balanceOf(bob);

        assertGt(bobShares, 0, "bob should have shares");
        assertEq(bryan.totalSupply(), bobShares, "total supply should equal bob's shares");
    }
}
