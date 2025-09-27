// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {
    AtLeastOneSideMustBeSponsor,
    DepositNotReady,
    InsufficientSponsorBalance,
    InvalidAuctionToken,
    FanToken,
    IERC20,
    IERC4626,
    IWETH9
} from "../src/FanToken.sol";
import {FanTokenFactory} from "../src/FanTokenFactory.sol";
import {Generic4626Router} from "../src/interfaces/Generic4626Router.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAuction} from "../src/interfaces/IAuction.sol";
import {console} from "forge-std/console.sol";

contract FanTokenTest is Test {
    using SafeERC20 for IERC20;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");
    address sponsor = makeAddr("sponsor");
    address sponsor1 = makeAddr("sponsor1");
    address sponsor2 = makeAddr("sponsor2");
    address sponsor3 = makeAddr("sponsor3");
    address nonSponsor = makeAddr("nonSponsor");
    address owner = makeAddr("owner");
    address treasury = makeAddr("treasury");

    IERC4626 prizeVault = IERC4626(0x4E42f783db2D0C5bDFf40fDc66FCAe8b1Cda4a43);
    IWETH9 constant WETH9 = IWETH9(payable(0x4200000000000000000000000000000000000006));
    Generic4626Router constant UNISWAP_V4_4626_HOOK =
        Generic4626Router(address(0xD60a6A0f0D5E3Fd451449C7256BbbDC59561e888));

    FanTokenFactory factory;
    FanToken public bryanFanToken;
    IERC20 underlying;

    function setUp() public {
        deal(owner, 10 ether);
        deal(address(this), 100_000 ether);

        // Use realistic fee values for thorough testing
        uint256 harvestOwnerFeeBasisPoints = 200; // 2%
        uint256 harvestTreasuryFeeBasisPoints = 300; // 3%

        factory = new FanTokenFactory(WETH9, UNISWAP_V4_4626_HOOK);

        vm.prank(owner);
        bryanFanToken = factory.create(
            "ETH from bryan",
            "BRY-ETH",
            harvestOwnerFeeBasisPoints,
            harvestTreasuryFeeBasisPoints,
            prizeVault,
            treasury,
            bytes32(0),
            0, // initial deposit
            false
        );

        underlying = bryanFanToken.UNDERLYING();

        vm.prank(sponsor);
        bryanFanToken.setSponsorship(true);

        vm.prank(sponsor1);
        bryanFanToken.setSponsorship(true);

        vm.prank(sponsor2);
        bryanFanToken.setSponsorship(true);

        vm.prank(sponsor3);
        bryanFanToken.setSponsorship(true);
    }

    /// @dev make sure the vault's underlying is weth
    function test_vault_asset() public view {
        assertEq(address(bryanFanToken.UNDERLYING()), address(WETH9), "underlying isn't weth");
    }

    function test_vault_starts_empty() public view {
        assertEq(bryanFanToken.totalSupply(), 0, "vault should start with zero total supply");
        assertEq(bryanFanToken.totalAssets(), 0, "vault should start with zero total assets");
    }

    function test_ownership() public {
        address nextOwner = makeAddr("nextOwner");

        // changing ownership from owner to nextOwner

        assertEq(owner, bryanFanToken.owner(), "initial owner should match expected owner");

        // make sure random accounts can't call transferOwnership
        vm.expectRevert();
        bryanFanToken.transferOwnership(nextOwner);

        // only the owner should be able to call transfer ownership
        vm.startPrank(owner);
        bryanFanToken.transferOwnership(nextOwner);

        // make sure acceptOwnership from other people fails
        vm.expectRevert();
        bryanFanToken.acceptOwnership();

        // only the next owner should be able to accept ownership
        vm.startPrank(nextOwner);
        bryanFanToken.acceptOwnership();

        // make sure the owner changed
        assertEq(nextOwner, bryanFanToken.owner(), "wrong new owner");
    }

    /// @dev helper function for turning underlying assets into erc4626 shares
    function _dealAsset(uint256 underlyingAssets, address receiver) internal returns (IERC4626 asset, uint256 assets) {
        deal(address(underlying), address(this), underlyingAssets, false);

        // asset == prize vault
        asset = IERC4626(bryanFanToken.asset());
        assertNotEq(address(asset), address(0), "asset should not be zero address");

        // approve and deposit the underlying to get the asset that backs bryanFanToken
        underlying.approve(address(asset), type(uint256).max);
        assets = asset.deposit(underlyingAssets, receiver);
    }

    /// @dev Helper function for deposit operations with proper Transfer event expectations
    function _depositWithEvents(uint256 assets, address receiver) internal returns (uint256 shares) {
        // Deposit operations emit two Transfer events:
        // 1. Mint to contract: Transfer(address(0), address(bryanFanToken), assets)
        // 2. Transfer to alice: Transfer(address(bryanFanToken), receiver, assets)
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(address(0), address(bryanFanToken), assets);
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(address(bryanFanToken), receiver, assets);
        return bryanFanToken.deposit(assets, receiver);
    }

    /// @dev Helper function for withdraw operations with proper Transfer event expectations
    function _withdrawWithEvents(uint256 assets, address to, address from) internal returns (uint256 shares) {
        uint256 expectedShares = bryanFanToken.previewWithdraw(assets);

        if (bryanFanToken.isSponsor(from)) {
            // Sponsor withdraw operations emit THREE Transfer events:
            // 1. Transfer(address(bryanFanToken), from, assets) - Contract to sponsor (assets)
            // 2. Transfer(from, address(0), expectedShares) - Burn shares from sponsor
            // 3. Transfer(address(bryanFanToken), to, assets) - Contract to recipient (final assets)
            vm.expectEmit(true, true, false, true);
            emit IERC20.Transfer(address(bryanFanToken), from, assets);
            vm.expectEmit(true, true, false, true);
            emit IERC20.Transfer(from, address(0), expectedShares);
            vm.expectEmit(true, true, false, true);
            emit IERC20.Transfer(address(bryanFanToken), to, assets);
        } else {
            // Non-sponsor withdraw operations emit TWO Transfer events:
            // 1. Transfer(from, address(0), shares) - Burn shares from alice
            // 2. Transfer(address(bryanFanToken), to, assets) - Transfer assets from contract to recipient
            vm.expectEmit(true, true, false, true);
            emit IERC20.Transfer(from, address(0), expectedShares);
            vm.expectEmit(true, true, false, true);
            emit IERC20.Transfer(address(bryanFanToken), to, assets);
        }
        return bryanFanToken.withdraw(assets, to, from);
    }

    /// @dev Helper function for redeem operations with proper Transfer event expectations
    function _redeemWithEvents(uint256 shares, address to, address from) internal returns (uint256 assets) {
        if (bryanFanToken.isSponsor(from)) {
            // Sponsor redeem operations emit THREE Transfer events:
            // 1. Transfer(address(bryanFanToken), from, shares) - Contract to sponsor
            // 2. Transfer(from, address(0), shares) - Burn from sponsor
            // 3. Transfer(address(bryanFanToken), to, assets) - Contract to recipient (underlying assets)
            uint256 expectedAssets = bryanFanToken.previewRedeem(shares);
            vm.expectEmit(true, true, false, true);
            emit IERC20.Transfer(address(bryanFanToken), from, shares);
            vm.expectEmit(true, true, false, true);
            emit IERC20.Transfer(from, address(0), shares);
            vm.expectEmit(true, true, false, true);
            emit IERC20.Transfer(address(bryanFanToken), to, expectedAssets);
        } else {
            // Non-sponsor redeem operations emit one Transfer event: Transfer(from, address(0), shares)
            vm.expectEmit(true, true, false, true);
            emit IERC20.Transfer(from, address(0), shares);
        }
        return bryanFanToken.redeem(shares, to, from);
    }

    function test_expected_default_sponsors() public view {
        assertEq(bryanFanToken.isSponsor(address(0)), false, "zero address should not be sponsor");
        assertEq(bryanFanToken.isSponsor(address(bryanFanToken)), false, "contract itself should not be sponsor"); // TODO: i'm unsure if we want this to be true or not. i think not
        assertEq(bryanFanToken.isSponsor(owner), true, "owner should be default sponsor");
        assertEq(bryanFanToken.isSponsor(treasury), true, "treasury should be default sponsor");
        assertEq(bryanFanToken.isSponsor(address(factory)), true, "factory should be default sponsor");
    }

    function test_multiple_users_depositing_without_sponsorship() public {
        // TODO: pick multiple amounts. and have users take different amounts. this should find any problems with rounding
        uint256 underlyingAssets = 1 ether;

        (IERC4626 asset, uint256 assets) = _dealAsset(underlyingAssets * 4, address(this));

        uint256 quarterAssets = assets / 4;
        assertEq(quarterAssets, underlyingAssets, "quarter assets should equal underlying assets (1 ether)");

        require(asset.transfer(alice, quarterAssets));
        require(asset.transfer(bob, quarterAssets));
        require(asset.transfer(charlie, quarterAssets));

        // todo: there might be 1 wei. i think thats fine
        assertEq(asset.balanceOf(address(this)), quarterAssets, "assets should have been sent to alice/bob/charlie");

        // get some tokens for alice
        vm.startPrank(alice);
        asset.approve(address(bryanFanToken), type(uint256).max);
        uint256 aliceWhen = bryanFanToken.startDeposit(quarterAssets);
        assertEq(aliceWhen, 0, "first deposit should be instant");

        uint256 aliceFanTokens = bryanFanToken.balanceOf(alice);
        assertEq(aliceFanTokens, quarterAssets, "alice should receive fan tokens equal to deposited assets");

        // check balances
        assertEq(bryanFanToken.balanceOfUnderlying(alice), quarterAssets, "alice initial deposit should work");
        assertEq(bryanFanToken.balanceOfUnderlying(bob), 0, "bob should have zero");
        assertEq(bryanFanToken.balanceOfUnderlying(charlie), 0, "charlie should have zero");

        // check sponsorship levels
        assertEq(bryanFanToken.isSponsor(alice), false, "alice must not be a sponsor");
        assertEq(bryanFanToken.isSponsor(bob), false, "bob must be a sponsor");
        assertEq(bryanFanToken.isSponsor(charlie), false, "charlie must not be a sponsor");

        // get some sponsor tokens for bob
        vm.startPrank(bob);
        asset.approve(address(bryanFanToken), type(uint256).max);
        uint256 bobWhen = bryanFanToken.startDeposit(quarterAssets);
        assertEq(bobWhen, block.timestamp + bryanFanToken.DEPOSIT_DELAY(), "unexpected deposit delay");

        // check balances
        assertEq(bryanFanToken.balanceOfUnderlying(alice), quarterAssets, "alice initial deposit should work");
        assertEq(bryanFanToken.balanceOfUnderlying(bob), 0, "bob should have zero");
        assertEq(bryanFanToken.balanceOfUnderlying(charlie), 0, "charlie should have zero");

        assertEq(bryanFanToken.balanceOfSponsorAssets(alice), 0, "alice should not have a sponsor balance");
        assertEq(bryanFanToken.balanceOfSponsorAssets(bob), 0, "bob should not have a sponsor balance");
        assertEq(bryanFanToken.balanceOfSponsorAssets(charlie), 0, "charlie should not have a sponsor balance");

        // TODO: this name should include "assets". and then balanceOfPendingAssets should be in shares.
        assertEq(bryanFanToken.balanceOfPendingAssets(alice), 0, "alice should not have a pending balance");
        assertEq(bryanFanToken.balanceOfPendingAssets(bob), quarterAssets, "bob should have a pending balance");
        assertEq(bryanFanToken.balanceOfPendingAssets(charlie), 0, "charlie should not have a pending balance");

        // fast forward and finalize deposit
        vm.warp(block.timestamp + bryanFanToken.DEPOSIT_DELAY());
        uint256 bobFanTokens = _depositWithEvents(quarterAssets, address(bob));
        assertEq(bobFanTokens, quarterAssets, "bob should receive fan tokens equal to deposited assets");

        assertEq(bryanFanToken.balanceOfUnderlying(alice), quarterAssets, "alice initial deposit should work");
        assertEq(bryanFanToken.balanceOfUnderlying(bob), quarterAssets, "bob should have a deposit now");
        assertEq(bryanFanToken.balanceOfUnderlying(charlie), 0, "charlie should still have zero");

        assertEq(bryanFanToken.balanceOfSponsorAssets(alice), 0, "alice should still not have a sponsor balance");
        assertEq(bryanFanToken.balanceOfSponsorAssets(bob), 0, "bob should still not have a sponsor balance now");
        assertEq(bryanFanToken.balanceOfSponsorAssets(charlie), 0, "charlie should still not have a sponsor balance");

        // get some tokens for charlie and then convert them to sponsor tokens
        vm.startPrank(charlie);
        asset.approve(address(bryanFanToken), type(uint256).max);
        uint256 charlieWhen = bryanFanToken.startDeposit(quarterAssets);

        assertEq(charlieWhen, block.timestamp + bryanFanToken.DEPOSIT_DELAY(), "charlie deposit delay wrong");

        // TODO: add some rewards to the contract and make sure that doesn't break any balances

        // fast forward and finalize deposit
        vm.warp(block.timestamp + bryanFanToken.DEPOSIT_DELAY());
        uint256 charlieFanTokens = bryanFanToken.deposit(quarterAssets, address(charlie));
        assertEq(charlieFanTokens, quarterAssets, "charlie should receive fan tokens equal to deposited assets");

        assertEq(
            bryanFanToken.balanceOfUnderlying(alice), quarterAssets, "alice should still have their original deposit"
        );
        assertEq(bryanFanToken.balanceOfUnderlying(bob), quarterAssets, "bob should still have their original deposit");
        assertEq(bryanFanToken.balanceOfUnderlying(charlie), quarterAssets, "charlie should now have a deposit");

        assertEq(
            bryanFanToken.balanceOfSponsorAssets(alice),
            0,
            "after charlie, alice should still not have a sponsor balance"
        );
        assertEq(
            bryanFanToken.balanceOfSponsorAssets(bob), 0, "after charlie, bob should still not have a sponsor balance"
        );
        assertEq(
            bryanFanToken.balanceOfSponsorAssets(charlie),
            0,
            "after charlie, charlie should still not have a sponsor balance"
        );

        // TODO: transfer tokens from alice to bob
        // TODO: transfer tokens from alice to charlie
        // TODO: transfer tokens from bob to alice
        // TODO: transfer tokens from bob to charlie
        // TODO: transfer tokens from charlie to alice
        // TODO: transfer tokens from charlie to bob
    }

    function test_multiple_users_depositing_with_sponsorship() public {
        // TODO: pick multiple amounts. and have users take different amounts. this should find any problems with rounding
        uint256 underlyingAssets = 1 ether;

        (IERC4626 asset, uint256 assets) = _dealAsset(underlyingAssets * 4, address(this));

        uint256 quarterAssets = assets / 4;
        assertEq(quarterAssets, underlyingAssets, "quarter assets should equal underlying assets (1 ether)");

        require(asset.transfer(alice, quarterAssets));
        require(asset.transfer(bob, quarterAssets));
        require(asset.transfer(charlie, quarterAssets));

        // todo: there might be 1 wei. i think thats fine
        assertEq(asset.balanceOf(address(this)), quarterAssets, "assets should have been sent to alice/bob/charlie");

        // get some tokens for alice
        vm.startPrank(alice);
        asset.approve(address(bryanFanToken), type(uint256).max);
        uint256 aliceWhen = bryanFanToken.startDeposit(quarterAssets);
        assertEq(aliceWhen, 0, "first deposit should be instant");

        uint256 aliceFanTokens = bryanFanToken.balanceOf(alice);
        assertEq(aliceFanTokens, quarterAssets, "alice should receive fan tokens equal to deposited assets");

        // check balances
        assertEq(bryanFanToken.balanceOfUnderlying(alice), quarterAssets, "alice initial deposit should work");
        assertEq(bryanFanToken.balanceOfUnderlying(bob), 0, "bob should have zero");
        assertEq(bryanFanToken.balanceOfUnderlying(charlie), 0, "charlie should have zero");

        // mark bob as a sponsor
        vm.startPrank(bob);
        bryanFanToken.setSponsorship(true);

        // check sponsorship levels
        assertEq(bryanFanToken.isSponsor(alice), false, "alice must not be a sponsor");
        assertEq(bryanFanToken.isSponsor(bob), true, "bob must be a sponsor");
        assertEq(bryanFanToken.isSponsor(charlie), false, "charlie must not be a sponsor");

        // get some sponsor tokens for bob
        asset.approve(address(bryanFanToken), type(uint256).max);
        uint256 bobWhen = bryanFanToken.startDeposit(quarterAssets);
        assertEq(bobWhen, block.timestamp + bryanFanToken.DEPOSIT_DELAY(), "unexpected deposit delay");

        // check balances
        assertEq(bryanFanToken.balanceOfUnderlying(alice), quarterAssets, "alice initial deposit should work");
        assertEq(bryanFanToken.balanceOfUnderlying(bob), 0, "bob should have zero");
        assertEq(bryanFanToken.balanceOfUnderlying(charlie), 0, "charlie should have zero");

        assertEq(bryanFanToken.balanceOfSponsorAssets(alice), 0, "alice should not have a sponsor balance");
        assertEq(bryanFanToken.balanceOfSponsorAssets(bob), 0, "bob should not have a sponsor balance");
        assertEq(bryanFanToken.balanceOfSponsorAssets(charlie), 0, "charlie should not have a sponsor balance");

        // TODO: this name should include "assets". and then balanceOfPendingAssets should be in shares.
        assertEq(bryanFanToken.balanceOfPendingAssets(alice), 0, "alice should not have a pending balance");
        assertEq(bryanFanToken.balanceOfPendingAssets(bob), quarterAssets, "bob should have a pending balance");
        assertEq(bryanFanToken.balanceOfPendingAssets(charlie), 0, "charlie should not have a pending balance");

        // fast forward and finalize deposit
        vm.warp(block.timestamp + bryanFanToken.DEPOSIT_DELAY());
        uint256 bobFanTokens = bryanFanToken.deposit(quarterAssets, address(bob));
        assertEq(bobFanTokens, quarterAssets, "bob should receive fan tokens equal to deposited assets");

        assertEq(bryanFanToken.balanceOfUnderlying(alice), quarterAssets, "alice initial deposit should work");
        assertEq(bryanFanToken.balanceOfUnderlying(bob), 0, "bob should still have zero");
        assertEq(bryanFanToken.balanceOfUnderlying(charlie), 0, "charlie should still have zero");

        assertEq(bryanFanToken.balanceOfSponsorAssets(alice), 0, "alice should still not have a sponsor balance");
        assertEq(bryanFanToken.balanceOfSponsorAssets(bob), quarterAssets, "bob should have a sponsor balance now");
        assertEq(bryanFanToken.balanceOfSponsorAssets(charlie), 0, "charlie should still not have a sponsor balance");

        // get some tokens for charlie and then convert them to sponsor tokens
        vm.startPrank(charlie);
        asset.approve(address(bryanFanToken), type(uint256).max);
        uint256 charlieWhen = bryanFanToken.startDeposit(quarterAssets);

        assertEq(charlieWhen, block.timestamp + bryanFanToken.DEPOSIT_DELAY(), "charlie deposit delay wrong");

        // we change set sponsorship during the delay queue
        // TODO: we should also have a test that changes sponsorship after the deposit is finalized
        bryanFanToken.setSponsorship(true);

        // TODO: add some rewards to the contract and make sure that doesn't break any balances

        // fast forward and finalize deposit
        vm.warp(block.timestamp + bryanFanToken.DEPOSIT_DELAY());
        uint256 charlieFanTokens = bryanFanToken.deposit(quarterAssets, address(charlie));
        assertEq(charlieFanTokens, quarterAssets, "charlie should receive fan tokens equal to deposited assets");

        assertEq(
            bryanFanToken.balanceOfUnderlying(alice), quarterAssets, "alice should still have their original deposit"
        );
        assertEq(bryanFanToken.balanceOfUnderlying(bob), 0, "bob is a sponsor and should have zero still");
        assertEq(
            bryanFanToken.balanceOfUnderlying(charlie),
            0,
            "charlie is a sponsor and should should still have zero still"
        );

        assertEq(
            bryanFanToken.balanceOfSponsorAssets(alice),
            0,
            "after charlie, alice should still not have a sponsor balance"
        );
        assertEq(
            bryanFanToken.balanceOfSponsorAssets(bob),
            quarterAssets,
            "after charlie, bob should have a sponsor balance now"
        );
        assertEq(
            bryanFanToken.balanceOfSponsorAssets(charlie),
            quarterAssets,
            "after charlie, charlie should have a sponsor balance now"
        );

        // TODO: transfer tokens from alice to bob
        // TODO: transfer tokens from alice to charlie
        // TODO: transfer tokens from bob to alice
        // TODO: transfer tokens from bob to charlie
        // TODO: transfer tokens from charlie to alice
        // TODO: transfer tokens from charlie to bob

        // TODO: turn off bob's sponsorship? we need a test that just does a single sponsor alice back and forth
    }

    function test_toggle_sponsorship() public {
        uint256 underlyingAssets = 1 ether;
        assertEq(underlyingAssets, 1 ether, "should be 1 ether of underlying assets");

        (IERC4626 asset, uint256 assets) = _dealAsset(underlyingAssets, address(this));
        assertEq(assets, underlyingAssets, "should deal exactly the underlying assets amount");

        asset.approve(address(bryanFanToken), type(uint256).max);
        uint256 when = bryanFanToken.startDeposit(assets);

        assertEq(when, 0, "this deposit should be instant");

        uint256 originalTotalSupply = bryanFanToken.totalSupply();
        assertEq(originalTotalSupply, underlyingAssets, "initial total supply should equal underlying assets");

        assertEq(bryanFanToken.balanceOfUnderlying(address(this)), underlyingAssets, "initial deposit amount");
        assertEq(
            bryanFanToken.balanceOfSponsorAssets(address(this)),
            0,
            "initial deposit amount shouldn't have any sponsorship"
        );
        assertEq(bryanFanToken.totalAssets(), assets, "initial deposit assets");
        assertEq(originalTotalSupply, underlyingAssets, "total supply should equal underlying assets");

        bryanFanToken.setSponsorship(true);

        assertEq(bryanFanToken.balanceOfUnderlying(address(this)), 0, "initial deposit amount");
        assertEq(
            bryanFanToken.balanceOfSponsorAssets(address(this)), underlyingAssets, "now it should have sponsorship"
        );
        assertEq(bryanFanToken.totalAssets(), assets, "total assets should be unchanged");
        assertEq(bryanFanToken.totalSupply(), originalTotalSupply, "total supply should be unchanged");

        bryanFanToken.setSponsorship(false);

        assertEq(bryanFanToken.balanceOfUnderlying(address(this)), underlyingAssets, "initial deposit amount");
        assertEq(bryanFanToken.balanceOfSponsorAssets(address(this)), 0, "now it should have sponsorship");
        assertEq(bryanFanToken.totalAssets(), assets, "total assets should still be unchanged");
        assertEq(bryanFanToken.totalSupply(), originalTotalSupply, "total supply should be still unchanged");
    }

    function test_deposit_and_withdraw() public {
        // TODO: for some reason we can't deal the ERC4626. We can deal the ERC20 though.
        uint256 underlyingAssets = 1 ether;
        (IERC4626 asset, uint256 assets) = _dealAsset(underlyingAssets, address(this));

        uint256 depositDelay = bryanFanToken.DEPOSIT_DELAY();

        asset.approve(address(bryanFanToken), type(uint256).max);

        uint256 shares = bryanFanToken.deposit(assets / 2, address(this));
        assertEq(shares, assets / 2, "shares minted should equal deposited assets");

        assertEq(bryanFanToken.totalSupply(), shares, "supply wrong 1");

        // todo: deposit without calling start should revert
        uint256 when = bryanFanToken.startDeposit(assets / 2, address(this));
        assertEq(when, block.timestamp + depositDelay, "second deposit availability mismatch");
        assertEq(bryanFanToken.balanceOfPendingAssets(address(this)), assets / 2, "finishing deposit failed");

        // Total supply should not increase until deposit is finalized
        assertEq(bryanFanToken.totalSupply(), shares, "supply should stay same until deposit finalized");

        vm.warp(block.timestamp + depositDelay);
        // TODO: test depositing from another address. anyone should be able to finalize a deposit
        uint256 newShares = bryanFanToken.deposit(assets / 2, address(this));
        assertEq(newShares, assets / 2, "second deposit should mint same number of shares");

        assertEq(bryanFanToken.balanceOfPendingAssets(address(this)), 0, "finishing deposit failed");

        assertEq(bryanFanToken.totalSupply(), shares + newShares, "supply wrong 3");

        // TODO: the fees make this annoying
        assertEq(asset.balanceOf(address(bryanFanToken)), assets, "asset balance does not match assets");
        assertEq(
            bryanFanToken.balanceOf(address(this)), shares + newShares, "bryanFanToken balance does not match shares"
        );
        assertApproxEqAbs(
            bryanFanToken.balanceOfUnderlying(address(this)), underlyingAssets, 1, "underlying balance does not match"
        );

        // test the main redeem function
        uint256 redeemed = _redeemWithEvents(shares + newShares, address(this), address(this));

        assertEq(redeemed, underlyingAssets, "should redeem the original deposit amount");
        assertApproxEqAbs(
            IERC20(bryanFanToken.asset()).balanceOf(address(bryanFanToken)),
            0,
            1,
            "token's asset balance should be empty"
        );
        assertEq(bryanFanToken.balanceOf(address(this)), 0, "our balance of bryanFanToken should be empty");
        assertApproxEqAbs(asset.balanceOf(address(this)), assets, 1, "we should have our asset back less the fee");
        assertEq(bryanFanToken.balanceOfUnderlying(address(this)), 0, "underlying balance is not zeroed");
    }

    function test_enableAuction_asset_fails() public {
        IERC20 from = IERC20(bryanFanToken.asset());

        vm.expectRevert(InvalidAuctionToken.selector);
        bryanFanToken.enableAuction(from);
    }

    function test_enableAuction_underlying_fails() public {
        IERC20 from = IERC20(address(bryanFanToken.UNDERLYING()));

        vm.expectRevert(InvalidAuctionToken.selector);
        bryanFanToken.enableAuction(from);
    }

    function test_enableAuction_self_fails() public {
        IERC20 from = IERC20(address(bryanFanToken));

        vm.expectRevert(InvalidAuctionToken.selector);
        bryanFanToken.enableAuction(from);
    }

    function test_auction_pool() public {
        IERC20 from = IERC20(0xd652C5425aea2Afd5fb142e120FeCf79e18fafc3); // POOL

        bryanFanToken.enableAuction(from);

        uint256 fromAmount = 1 ether;
        assertEq(fromAmount, 1 ether, "test assumes an auction size of 1 ether");

        deal(address(from), address(bryanFanToken), fromAmount, true);

        assertEq(bryanFanToken.kickable(address(from)), fromAmount, "kickable amount wrong");

        // Test auctionTrigger before kicking
        (bool shouldKick, bytes memory triggerData) = bryanFanToken.auctionTrigger(address(from));
        assertTrue(shouldKick, "auctionTrigger should return true for kickable amount");
        assertNotEq(triggerData.length, 0, "trigger data should not be empty");

        IAuction auction = IAuction(bryanFanToken.auction());
        require(address(auction) != address(0), "no auction contract");

        // TODO: compare encoding bryanFanToken.KickAuction to triggerData.
        uint256 available = bryanFanToken.kickAuction(address(from));

        assertEq(fromAmount, available, "auction size incorrect");

        // TODO: wait until a specific price?
        vm.warp(block.timestamp + 12 hours);

        address want = auction.want();
        assertEq(want, address(bryanFanToken.UNDERLYING()), "wrong want");
        assertEq(want, address(WETH9), "want isn't weth9");

        // prepare approvals
        IERC20(want).approve(address(auction), type(uint256).max);

        uint256 auctionAmountNeeded = auction.getAmountNeeded(address(from), fromAmount);
        assertGt(auctionAmountNeeded, 0, "want amount should be nonzero");

        // cheat to have the necessary tokens to fulfill the auction
        startHoax(address(this), auctionAmountNeeded);
        WETH9.deposit{value: auctionAmountNeeded}();

        // complete the auction
        uint256 amountFromTaken = auction.take(address(from));
        assertEq(amountFromTaken, fromAmount, "from amount error");

        // the old code had a postTake hook. the new code does not!
        // thanks to the post take hook, this was deposited
        // assertEq(IERC20(want).balanceOf(address(bryanFanToken)), 0, "want balance should be 0");

        // TODO: assert more things about the value
        assertGt(amountFromTaken, 0, "from taken should be nonzero");
    }

    function test_empty_harvest() public {
        assertEq(bryanFanToken.harvest(), 0);
    }

    function test_harvest_eth() public {
        require(address(bryanFanToken.UNDERLYING()) == address(WETH9), "not weth");

        uint256 amount = 1 ether;

        assertEq(bryanFanToken.harvest{value: amount}(), amount, "incorrect eth harvest amount");

        // TODO: assert that the share price went up properly
    }

    function test_harvest_weth() public {
        require(address(bryanFanToken.UNDERLYING()) == address(WETH9), "not weth");

        uint256 amount = 1 ether;

        WETH9.deposit{value: amount}();
        require(WETH9.transfer(address(bryanFanToken), amount), "weth transfer failed");

        assertEq(bryanFanToken.harvest(), amount, "incorrect weth harvest amount");

        // TODO: assert that the share price went up properly
    }

    function test_wrapping_eth(uint256 value) public {
        // TODO: what is the actual max? something involving weth's totalSupply
        vm.assume(value < 100 ether);
        vm.assume(value > 0); // we call wrapETH at the start and end, so no real point in skipping it

        vm.deal(address(this), value);

        assertEq(bryanFanToken.wrapETH(), 0);
        assertEq(WETH9.balanceOf(address(bryanFanToken)), 0);

        assertEq(bryanFanToken.wrapETH{value: value}(), value);
        assertEq(WETH9.balanceOf(address(bryanFanToken)), value);

        assertEq(bryanFanToken.wrapETH(), 0);
        assertEq(WETH9.balanceOf(address(bryanFanToken)), value);
    }

    function test_harvest_with_both_fees() public {
        uint256 initialDeposit = 10 ether;

        vm.prank(owner);
        FanToken testFanToken = factory.create{value: initialDeposit}(
            "Both Fees Test",
            "BOTH",
            5000, // 50% owner fee
            5000, // 50% treasury fee
            IERC4626(bryanFanToken.asset()),
            treasury,
            bytes32(0),
            initialDeposit,
            false
        );

        vm.prank(owner);
        testFanToken.setSponsorship(false);

        assertEq(testFanToken.totalSupply(), initialDeposit, "initial total supply should equal deposited assets");
        assertEq(testFanToken.balanceOf(owner), initialDeposit, "initial owner balance should equal deposited assets");

        // fake rewards
        uint256 rewardAmount = 1 ether;
        vm.deal(address(testFanToken), rewardAmount);

        // Harvest
        uint256 harvested = testFanToken.harvest();
        assertEq(harvested, rewardAmount, "should harvest all rewards");
        assertEq(testFanToken.totalSupply(), initialDeposit, "total supply should not change after harvest");

        assertEq(
            prizeVault.previewRedeem(prizeVault.balanceOf(owner)),
            rewardAmount / 2,
            "owner fee balance should get half the rewards"
        );
        assertEq(
            prizeVault.balanceOf(treasury),
            prizeVault.balanceOf(owner),
            "treasury fee balance should increase the same as the owner's"
        );

        // Both owner and treasury should get fees in assets now
        // TODO: reward amount is in the underlying, but we need to convert this to shares
        assertEq(
            prizeVault.balanceOf(owner), prizeVault.previewWithdraw(rewardAmount / 2), "owner should get asset fee"
        );
        assertEq(
            prizeVault.balanceOf(treasury),
            prizeVault.previewWithdraw(rewardAmount / 2),
            "treasury should get asset fee"
        );
    }

    /// TODO: clean up this ai slop
    function test_sponsor_burn() public {
        uint256 depositAmount = 1 ether;
        (IERC4626 asset, uint256 assets) = _dealAsset(depositAmount, sponsor);

        vm.startPrank(sponsor);
        asset.approve(address(bryanFanToken), type(uint256).max);
        bryanFanToken.deposit(assets, sponsor);

        uint256 sponsorBalance = bryanFanToken.balanceOfSponsorAssets(sponsor);

        assertGt(sponsorBalance, 0, "there should be some sponsor balance");

        bryanFanToken.sponsorBurn(sponsorBalance / 2);

        assertEq(
            bryanFanToken.balanceOfSponsorAssets(sponsor),
            sponsorBalance / 2,
            "half the balance should have been burned"
        );
    }

    /// @dev Trying  to burn more than balance should fail
    function test_sponsor_burn_insufficient_balance() public {
        uint256 depositAmount = 1 ether;
        (IERC4626 asset, uint256 assets) = _dealAsset(depositAmount, sponsor);

        vm.startPrank(sponsor);
        asset.approve(address(bryanFanToken), type(uint256).max);
        bryanFanToken.deposit(assets, sponsor);

        uint256 sponsorBalance = bryanFanToken.balanceOfSponsorAssets(sponsor);

        assertGt(sponsorBalance, 0, "there should be some sponsor balance");

        vm.expectRevert();
        bryanFanToken.sponsorBurn(sponsorBalance + 1);
    }

    // Set up scenario: sponsor and non-sponsor users, then send rewards to trigger harvestSponsorship
    function test_harvestSponsorship_with_rewards() public {
        uint256 depositAmount = 1 ether;
        (IERC4626 asset,) = _dealAsset(depositAmount * 4, address(this));

        // Give assets to all users
        require(asset.transfer(sponsor, depositAmount));
        require(asset.transfer(alice, depositAmount), "asset transfer failed");
        require(asset.transfer(bob, depositAmount));

        // Non-sponsors deposit first with proper timing
        vm.startPrank(alice);
        asset.approve(address(bryanFanToken), type(uint256).max);
        uint256 aliceWhen = bryanFanToken.startDeposit(depositAmount, alice);
        // Alice should be the first deposit, so immediate
        assertEq(aliceWhen, 0, "alice first deposit should be immediate");

        vm.startPrank(bob);
        asset.approve(address(bryanFanToken), type(uint256).max);
        uint256 bobWhen = bryanFanToken.startDeposit(depositAmount, bob);
        // Bob deposit should be delayed since Alice already deposited
        assertGt(bobWhen, 0, "bob deposit should be delayed");
        vm.warp(bobWhen);
        bryanFanToken.deposit(depositAmount, bob);

        // Sponsor deposits with proper timing
        vm.startPrank(sponsor);
        asset.approve(address(bryanFanToken), type(uint256).max);
        uint256 sponsorWhen = bryanFanToken.startDeposit(depositAmount, sponsor);
        // Sponsor deposit should be delayed since others already deposited
        assertGt(sponsorWhen, 0, "sponsor deposit should be delayed");
        vm.warp(sponsorWhen);
        bryanFanToken.deposit(depositAmount, sponsor);

        // Record initial state
        uint256 initialSponsorAssets = bryanFanToken.balanceOfSponsorAssets(sponsor);
        uint256 initialAliceUnderlying = bryanFanToken.balanceOfUnderlying(alice);
        uint256 initialBobUnderlying = bryanFanToken.balanceOfUnderlying(bob);

        // Send fake rewards to the contract using transfer
        uint256 rewardAmount = 0.5 ether;

        vm.deal(address(this), rewardAmount);
        WETH9.deposit{value: rewardAmount}();
        require(WETH9.transfer(address(bryanFanToken), rewardAmount), "weth transfer failed");

        // Harvest - this should trigger harvestSponsorship automatically
        assertEq(bryanFanToken.harvest(), rewardAmount, "should harvest all rewards");

        // Key verification: sponsor balance should remain the same in underlying value
        assertEq(
            bryanFanToken.balanceOfSponsorAssets(sponsor), initialSponsorAssets, "sponsor assets should remain the same"
        );

        // Calculate exact expected rewards for non-sponsors
        uint256 finalAliceUnderlying = bryanFanToken.balanceOfUnderlying(alice);
        uint256 finalBobUnderlying = bryanFanToken.balanceOfUnderlying(bob);
        uint256 aliceGain = finalAliceUnderlying - initialAliceUnderlying;
        uint256 bobGain = finalBobUnderlying - initialBobUnderlying;

        // Both Alice and Bob have equal shares, so should get equal rewards (minus fees)
        // Since they have equal positions, their gains should be equal
        assertEq(aliceGain, bobGain, "alice and bob should gain exactly equal amounts from harvest");

        // Both should receive reasonable portion of rewards
        // TODO: assert the actual amounts instead of using Gt/Lt
        assertGt(aliceGain, rewardAmount / 4, "alice should get substantial portion of rewards");
        assertGt(bobGain, rewardAmount / 4, "bob should get substantial portion of rewards");
        assertLt(aliceGain + bobGain, rewardAmount, "combined gains should be less than total reward due to fees");
    }

    /// @dev Test with multiple sponsors to ensure proper accounting
    function test_harvestSponsorship_multiple_sponsors() public {
        uint256 depositAmount = 1 ether;
        (IERC4626 asset,) = _dealAsset(depositAmount * 4, address(this));

        // Distribute assets
        require(asset.transfer(sponsor1, depositAmount), "asset transfer failed");
        require(asset.transfer(sponsor2, depositAmount), "asset transfer failed");
        require(asset.transfer(alice, depositAmount), "asset transfer failed");

        // Alice (non-sponsor) deposits first with proper timing
        vm.startPrank(alice);
        asset.approve(address(bryanFanToken), type(uint256).max);
        uint256 aliceWhen = bryanFanToken.startDeposit(depositAmount, alice);
        assertEq(aliceWhen, 0, "alice first deposit should be immediate");

        // First sponsor deposits with proper timing
        vm.startPrank(sponsor1);
        asset.approve(address(bryanFanToken), type(uint256).max);
        uint256 sponsor1When = bryanFanToken.startDeposit(depositAmount, sponsor1);
        assertGt(sponsor1When, 0, "first sponsor deposit should be delayed");
        vm.warp(sponsor1When);
        bryanFanToken.deposit(depositAmount, sponsor1);

        // Second sponsor deposits with proper timing
        vm.startPrank(sponsor2);
        asset.approve(address(bryanFanToken), type(uint256).max);
        uint256 sponsor2When = bryanFanToken.startDeposit(depositAmount, sponsor2);
        assertGt(sponsor2When, 0, "second sponsor deposit should be delayed");
        vm.warp(sponsor2When);
        bryanFanToken.deposit(depositAmount, sponsor2);

        uint256[3] memory preBalances;
        preBalances[0] = bryanFanToken.balanceOfUnderlying(alice);
        preBalances[1] = bryanFanToken.balanceOfSponsorAssets(sponsor1);
        preBalances[2] = bryanFanToken.balanceOfSponsorAssets(sponsor2);

        uint256 rewardAmount = 1 ether;

        vm.deal(address(this), rewardAmount);
        WETH9.deposit{value: rewardAmount}();
        require(WETH9.transfer(address(bryanFanToken), rewardAmount), "weth transfer failed");

        uint256 harvested = bryanFanToken.harvest();
        assertEq(harvested, rewardAmount, "should harvest all rewards");

        uint256[3] memory postBalances;
        postBalances[0] = bryanFanToken.balanceOfUnderlying(alice);
        postBalances[1] = bryanFanToken.balanceOfSponsorAssets(sponsor1);
        postBalances[2] = bryanFanToken.balanceOfSponsorAssets(sponsor2);

        assertEq(postBalances[1], preBalances[1], "sponsor1 assets should remain constant");
        assertEq(postBalances[2], preBalances[2], "sponsor2 assets should remain constant");

        uint256 aliceGain = postBalances[0] - preBalances[0];
        assertGt(aliceGain, rewardAmount / 2, "alice should get substantial portion of rewards");
        assertLt(aliceGain, rewardAmount, "alice should not get more than total rewards");
    }

    function test_sponsor_transfer_success() public {
        // Set up sponsor with assets
        (IERC4626 asset, uint256 assets) = _dealAsset(1 ether, sponsor1);

        vm.startPrank(sponsor1);
        asset.approve(address(bryanFanToken), type(uint256).max);
        uint256 when = bryanFanToken.startDeposit(assets, sponsor1);
        // This should be the first deposit, so it should be immediate
        assertEq(when, 0, "first deposit should be immediate");
        // For immediate deposits, startDeposit already completed the deposit

        // Get sponsor's actual asset balance and transfer half
        uint256 sponsor1Assets = bryanFanToken.balanceOfSponsorAssets(sponsor1);

        assertEq(sponsor1Assets, assets, "initial deposit balance");

        uint256 transferAmount = sponsor1Assets / 2;
        assertGt(transferAmount, 0, "transfer amount should be positive");

        console.log("Before transfer:");
        console.log("  Sponsor assets:", sponsor1Assets);
        console.log("  Transfer amount:", transferAmount);

        vm.startPrank(sponsor1);
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(sponsor1, sponsor2, transferAmount);
        bryanFanToken.sponsorTransfer(sponsor2, transferAmount);

        // Verify transfer
        assertEq(
            bryanFanToken.balanceOfSponsorAssets(sponsor1),
            sponsor1Assets - transferAmount,
            "sponsor assets should decrease"
        );
        assertEq(
            bryanFanToken.balanceOfSponsorAssets(sponsor2),
            transferAmount,
            "recipient should receive transferred assets"
        );
    }

    function test_deposit_delay_constant() public view {
        assertEq(bryanFanToken.DEPOSIT_DELAY(), 3 days);
    }

    function test_claiming_pool_rewards() public {
        // Since we don't have actual POOL rewards in test, just verify the harvest function works
        uint256 initialBalance = WETH9.balanceOf(address(bryanFanToken));

        // Send some WETH to simulate rewards
        vm.deal(address(this), 1 ether);
        WETH9.deposit{value: 1 ether}();
        require(WETH9.transfer(address(bryanFanToken), 1 ether));

        uint256 harvested = bryanFanToken.harvest();
        assertEq(harvested, 1 ether, "should harvest exactly 1 ether of rewards");
        assertEq(WETH9.balanceOf(address(bryanFanToken)), initialBalance);
    }

    function test_withdraw_sponsor() public {
        (IERC4626 asset, uint256 assets) = _dealAsset(10 ether, sponsor);

        vm.startPrank(sponsor);
        bryanFanToken.setSponsorship(true);
        asset.approve(address(bryanFanToken), type(uint256).max);

        uint256 when = bryanFanToken.startDeposit(assets, sponsor);
        // This should be the first deposit, so immediate
        assertEq(when, 0, "first deposit should be immediate");

        uint256 sponsorShares = bryanFanToken.balanceOf(sponsor);
        uint256 sponsorAssets = bryanFanToken.balanceOfSponsorAssets(sponsor);

        // For sponsors, shares are held by contract but they have sponsor assets
        assertEq(sponsorShares, 0, "sponsor should have 0 direct shares (held by contract)");
        assertEq(sponsorAssets, assets, "sponsor should have exact deposited amount as sponsor assets");

        uint256 withdrawAmount = sponsorAssets / 2; // withdraw half of sponsor assets
        uint256 initialTotalSponsoredShares = bryanFanToken.totalSponsoredShares();
        uint256 initialTotalSponsoredAssets = bryanFanToken.totalSponsoredAssets();

        uint256 withdrawn = bryanFanToken.withdraw(withdrawAmount, sponsor, sponsor);

        uint256 sponsorSharesAfter = bryanFanToken.balanceOf(sponsor);
        uint256 sponsorAssetsAfter = bryanFanToken.balanceOfSponsorAssets(sponsor);

        assertEq(sponsorSharesAfter, 0, "sponsor should still have 0 direct shares after withdrawal");
        assertEq(withdrawn, withdrawAmount, "should receive exact withdrawn amount");
        assertEq(sponsorAssetsAfter, sponsorAssets - withdrawAmount, "remaining sponsor assets should be exact");

        // Verify total sponsored amounts decreased by exactly the withdrawal
        assertEq(
            bryanFanToken.totalSponsoredAssets(),
            initialTotalSponsoredAssets - withdrawAmount,
            "total sponsored assets should decrease by withdrawal amount"
        );
        assertLt(
            bryanFanToken.totalSponsoredShares(),
            initialTotalSponsoredShares,
            "total sponsored shares should decrease after withdrawal"
        );
    }

    // transfer between two sponsors
    function test_sponsorTransferFrom_success() public {
        uint256 totalSupply = 10 ether;
        uint256 transferAmount = 1 ether;

        (IERC4626 asset, uint256 assets) = _dealAsset(totalSupply, sponsor1);

        vm.startPrank(sponsor1);
        bryanFanToken.setSponsorship(true);
        asset.approve(address(bryanFanToken), type(uint256).max);

        uint256 when = bryanFanToken.startDeposit(assets);
        if (when > 0) {
            vm.warp(when);
            bryanFanToken.deposit(assets, sponsor1);
        }

        vm.startPrank(sponsor2);
        bryanFanToken.setSponsorship(true);

        assertEq(bryanFanToken.balanceOfSponsorAssets(sponsor1), assets, "sponsor 1 should have the initial deposit");
        assertEq(bryanFanToken.balanceOfSponsorAssets(sponsor2), 0, "sponsor 2 shouldn't have any balance to start");

        // Approve sponsor2 to transfer from sponsor1
        vm.startPrank(sponsor1);
        bryanFanToken.approve(sponsor2, transferAmount);

        // Transfer from sponsor1 to sponsor2
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(sponsor1, sponsor2, transferAmount);
        vm.startPrank(sponsor2);
        bool success = bryanFanToken.sponsorTransferFrom(sponsor1, sponsor2, transferAmount);
        assertTrue(success, "sponsorTransferFrom should return true on successful transfer");

        assertEq(
            bryanFanToken.balanceOfSponsorAssets(sponsor1), assets - transferAmount, "sponsor 1 should still have 9/10"
        );
        assertEq(
            bryanFanToken.balanceOfSponsorAssets(sponsor2),
            transferAmount,
            "sponsor 2 should have the amount of one transfer"
        );
        assertEq(bryanFanToken.allowance(sponsor1, sponsor2), 0, "there shouldnt be any allowance left");
        assertEq(
            bryanFanToken.totalSponsoredShares(),
            assets,
            "Total sponsored shares are held by the contract, not individual sponsors"
        );
    }

    function test_sponsorTransferFrom_insufficient_allowance() public {
        (IERC4626 asset, uint256 assets) = _dealAsset(10 ether, sponsor1);

        asset.approve(address(bryanFanToken), type(uint256).max);
        uint256 when = bryanFanToken.startDeposit(assets, sponsor1);
        if (when > 0) {
            vm.warp(when);
            bryanFanToken.deposit(assets, sponsor1);
        }

        vm.startPrank(sponsor2);
        bryanFanToken.setSponsorship(true);

        // Try to transfer without approval
        uint256 transferAmount = 1 ether; // Try to transfer a specific amount
        vm.startPrank(sponsor2);
        vm.expectRevert(); // Should fail due to insufficient allowance
        bryanFanToken.sponsorTransferFrom(sponsor1, sponsor2, transferAmount);
    }

    /// TODO: clean up this ai slop
    function test_totalSponsoredShares_and_totalSponsoredAssets() public {
        assertEq(bryanFanToken.totalSponsoredShares(), 0);
        assertEq(bryanFanToken.totalSponsoredAssets(), 0);

        (IERC4626 asset, uint256 totalAssets) = _dealAsset(15 ether, address(this));
        uint256 assets1 = (totalAssets * 2) / 3; // 10 ether worth
        uint256 assets2 = totalAssets - assets1; // 5 ether worth

        require(asset.transfer(sponsor1, assets1));
        require(asset.transfer(sponsor2, assets2));

        vm.startPrank(sponsor1);
        bryanFanToken.setSponsorship(true);
        asset.approve(address(bryanFanToken), type(uint256).max);
        uint256 when1 = bryanFanToken.startDeposit(assets1, sponsor1);
        if (when1 > 0) {
            vm.warp(when1);
            bryanFanToken.deposit(assets1, sponsor1);
        }

        vm.startPrank(sponsor2);
        bryanFanToken.setSponsorship(true);
        asset.approve(address(bryanFanToken), type(uint256).max);

        // After sponsor1 deposits and sponsor2 becomes a sponsor,
        // sponsor1's shares should be moved to the contract
        uint256 contractShares = bryanFanToken.totalSponsoredShares();
        assertGt(contractShares, 0, "contract should hold some sponsored shares after sponsor deposit");
        assertEq(bryanFanToken.totalSponsoredAssets(), bryanFanToken.convertToAssets(contractShares));

        // Deposit for sponsor2
        uint256 when2 = bryanFanToken.startDeposit(assets2, sponsor2);
        if (when2 > 0) {
            vm.warp(when2);
            bryanFanToken.deposit(assets2, sponsor2);
        }

        // After both sponsors deposit, all shares should be in the contract
        uint256 totalContractShares = bryanFanToken.totalSponsoredShares();
        assertGt(
            totalContractShares, contractShares, "total sponsored shares should increase after second sponsor deposit"
        );
        assertEq(bryanFanToken.totalSponsoredAssets(), bryanFanToken.convertToAssets(totalContractShares));
    }

    function test_finishDeposit_for_another_user() public {
        address depositor = makeAddr("depositor");
        address finisher = makeAddr("finisher");

        // Ensure this is NOT the first deposit to the contract
        // by making a small deposit first
        (IERC4626 asset, uint256 initialAssets) = _dealAsset(0.1 ether, address(this));
        asset.approve(address(bryanFanToken), type(uint256).max);
        bryanFanToken.deposit(initialAssets, address(this));

        // Now set up the actual test
        ( /*IERC4626 asset2*/ , uint256 assets) = _dealAsset(1 ether, address(this));
        require(asset.transfer(depositor, assets));

        // Depositor requests sponsorship and starts deposit
        vm.startPrank(depositor);
        bryanFanToken.setSponsorship(true);
        asset.approve(address(bryanFanToken), type(uint256).max);

        uint256 when = bryanFanToken.startDeposit(assets, depositor);

        assertGt(when, block.timestamp, "deposit should have delay after initial deposit");

        // Warp to when deposit is ready
        vm.warp(when);

        // Different alice (finisher) calls finishDeposit for the depositor
        vm.startPrank(finisher);
        uint256 finishedDeposit = bryanFanToken.finishDeposit(depositor, depositor);

        assertEq(finishedDeposit, assets, "should finish deposit of original amount");

        // Since depositor became a sponsor, their shares should be moved to the contract
        uint256 contractSponsoredShares = bryanFanToken.totalSponsoredShares();
        assertGt(contractSponsoredShares, 0, "contract should hold sponsored shares after sponsor deposit");
        assertGt(bryanFanToken.totalSponsoredAssets(), 0, "sponsored assets should be tracked after sponsor deposit");

        // Depositor's direct balance should be zero since they're a sponsor
        uint256 depositorBalanceAfter = bryanFanToken.balanceOf(depositor);
        assertEq(
            depositorBalanceAfter,
            0,
            "sponsor depositor should have zero direct balance, shares moved to sponsored pool"
        );
    }

    function test_harvesting_weth() public {
        // Add WETH to contract and sweep it
        vm.deal(address(this), 2 ether);
        WETH9.deposit{value: 2 ether}();
        require(WETH9.transfer(address(bryanFanToken), 2 ether));

        uint256 initialContractBalance = bryanFanToken.totalAssets();
        uint256 harvested = bryanFanToken.harvest();

        assertEq(harvested, 2 ether, "should harvest exactly 2 ether of WETH rewards");
        assertGt(bryanFanToken.totalAssets(), initialContractBalance);
    }

    function test_initial_total_sponsor_assets() public view {
        assertEq(bryanFanToken.totalSponsorAssets(), 0);
    }

    function test_version() public {
        string memory factoryVersion = bryanFanToken.FACTORY().version();
        string memory tokenVersion = bryanFanToken.version();
        assertEq(factoryVersion, "3.0.0", "factory version should be 3.0.0");
        assertEq(tokenVersion, factoryVersion, "token version should match factory version");
    }

    function test_harvest_empty_contract() public {
        uint256 harvested = bryanFanToken.harvest();
        assertEq(harvested, 0, "harvest should return 0 when contract is empty");
    }

    function test_sponsor_burn_zero_amount() public {
        vm.startPrank(sponsor);
        bryanFanToken.setSponsorship(true);

        // Burning 0 should succeed (it just does nothing)
        bryanFanToken.sponsorBurn(0);
        assertEq(bryanFanToken.balanceOfSponsorAssets(sponsor), 0, "sponsor should have 0 assets");
    }

    /// @dev Test that when a sponsor burns tokens, the share value for regular users increases
    function test_sponsor_burn_increases_share_value() public {
        uint256 depositAmount = 1 ether;

        // Deal assets and distribute
        (IERC4626 asset, uint256 sponsorAssets) = _dealAsset(depositAmount, sponsor);
        ( /*IERC4626 asset*/ , uint256 aliceAssets) = _dealAsset(depositAmount, alice);

        assertEq(sponsorAssets, aliceAssets, "sponsor and alice should have the same starting balances");

        // Alice deposits first (will be instant since it's first deposit)
        vm.startPrank(alice);
        asset.approve(address(bryanFanToken), type(uint256).max);
        bryanFanToken.deposit(depositAmount, alice);

        // Sponsor becomes sponsor and deposits
        vm.startPrank(sponsor);
        bryanFanToken.setSponsorship(true);
        asset.approve(address(bryanFanToken), type(uint256).max);
        uint256 sponsorWhen = bryanFanToken.startDeposit(depositAmount, sponsor);
        if (sponsorWhen > 0) {
            vm.warp(sponsorWhen);
            bryanFanToken.deposit(depositAmount, sponsor);
        }

        uint256 initialAliceUnderlying = bryanFanToken.balanceOfUnderlying(alice);

        console.log("Before burn:");
        console.log("  Alice underlying:", initialAliceUnderlying);
        console.log("  Sponsor assets:", sponsorAssets);

        assertGt(sponsorAssets, 0, "sponsor should have assets");

        // Sponsor burns half their assets
        uint256 burnAmount = sponsorAssets / 2;
        bryanFanToken.sponsorBurn(burnAmount);

        uint256 finalAliceUnderlying = bryanFanToken.balanceOfUnderlying(alice);
        uint256 finalSponsorAssets = bryanFanToken.balanceOfSponsorAssets(sponsor);

        console.log("After burn:");
        console.log("  Alice underlying:", finalAliceUnderlying);
        console.log("  Sponsor assets:", finalSponsorAssets);

        // TODO: specific assetions instead of just confirming that it grew
        assertEq(finalSponsorAssets, sponsorAssets - burnAmount, "sponsor assets should decrease");
        assertGt(finalAliceUnderlying, initialAliceUnderlying, "alice underlying should increase");
    }

    /// @dev Test depositing, redeeming 100%, then another alice depositing again
    function test_deposit_redeem_all_then_new_deposit() public {
        uint256 depositAmount = 2 ether;

        // Deal assets
        (IERC4626 asset,) = _dealAsset(depositAmount * 3, address(this));
        IERC20(address(asset)).safeTransfer(alice, depositAmount);
        IERC20(address(asset)).safeTransfer(bob, depositAmount);

        // Alice deposits first (instant since it's the first deposit)
        vm.startPrank(alice);
        asset.approve(address(bryanFanToken), type(uint256).max);
        bryanFanToken.deposit(depositAmount, alice);

        uint256 aliceShares = bryanFanToken.balanceOf(alice);

        assertGt(aliceShares, 0, "alice should have shares");
        assertGt(bryanFanToken.totalSupply(), 0, "should have total supply");

        // Alice redeems all her shares
        bryanFanToken.redeem(aliceShares, alice, alice);

        assertEq(bryanFanToken.balanceOf(alice), 0, "alice should have no shares");
        assertEq(bryanFanToken.totalSupply(), 0, "total supply should be zero");

        // TODO: have a similar test that harvests some prizes here!

        // Bob deposits after total supply went to zero (should be instant like first deposit)
        vm.startPrank(bob);
        asset.approve(address(bryanFanToken), type(uint256).max);
        bryanFanToken.deposit(depositAmount, bob);

        uint256 bobShares = bryanFanToken.balanceOf(bob);

        assertGt(bobShares, 0, "bob should have shares");
        assertEq(bryanFanToken.totalSupply(), bobShares, "total supply should equal bob's shares");
    }

    function test_sponsorTransfer_from_sponsor_to_nonsponsor() public {
        // Set up sponsor with assets
        (IERC4626 asset, uint256 assets) = _dealAsset(2 ether, address(this));
        require(asset.transfer(sponsor, assets), "asset transfer failed");

        vm.startPrank(sponsor);
        bryanFanToken.setSponsorship(true);
        asset.approve(address(bryanFanToken), type(uint256).max);

        uint256 when = bryanFanToken.startDeposit(assets, sponsor);
        if (when > 0) {
            vm.warp(when);
            bryanFanToken.finishDeposit(sponsor, sponsor);
        }

        uint256 sponsorAssets = bryanFanToken.balanceOfSponsorAssets(sponsor);
        uint256 transferAmount = sponsorAssets / 2;

        console.log("Before transfer (sponsor -> non-sponsor):");
        console.log("  Sponsor assets:", sponsorAssets);
        console.log("  Non-sponsor balance:", bryanFanToken.balanceOf(nonSponsor));
        console.log("  Transfer amount:", transferAmount);

        assertGt(sponsorAssets, 0, "sponsor should have assets");
        assertEq(bryanFanToken.balanceOf(nonSponsor), 0, "non-sponsor should start with zero balance");

        // Transfer from sponsor to non-sponsor
        bryanFanToken.sponsorTransfer(nonSponsor, transferAmount);

        // After transferring half, sponsor should have the remaining half
        assertEq(
            bryanFanToken.balanceOfSponsorAssets(sponsor),
            sponsorAssets - transferAmount,
            "sponsor should have remaining assets after transfer"
        );
        assertEq(
            bryanFanToken.balanceOfUnderlying(nonSponsor),
            transferAmount,
            "non sponsor should receive transferred underlying"
        );
    }

    function test_sponsorTransfer_from_nonsponsor_to_sponsor() public {
        // Set up non-sponsor with assets first
        (IERC4626 asset, uint256 assets) = _dealAsset(2 ether, nonSponsor);

        vm.startPrank(nonSponsor);
        asset.approve(address(bryanFanToken), type(uint256).max);

        uint256 when = bryanFanToken.startDeposit(assets, nonSponsor);
        if (when > 0) {
            vm.warp(when);
            bryanFanToken.deposit(assets, nonSponsor);
        }

        uint256 nonSponsorShares = bryanFanToken.balanceOf(nonSponsor);
        uint256 transferAmount = bryanFanToken.convertToAssets(nonSponsorShares / 2);

        console.log("Before transfer (non-sponsor -> sponsor):");
        console.log("  Non-sponsor shares:", nonSponsorShares);
        console.log("  Sponsor assets:", bryanFanToken.balanceOfSponsorAssets(sponsor));
        console.log("  Transfer amount:", transferAmount);

        assertGt(nonSponsorShares, 0, "non-sponsor should have shares");
        assertEq(bryanFanToken.balanceOfSponsorAssets(sponsor), 0, "sponsor should start with zero sponsor assets");

        // Set sponsor status for recipient
        vm.startPrank(sponsor);
        bryanFanToken.setSponsorship(true);

        // Transfer from non-sponsor to sponsor
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(nonSponsor, sponsor, bryanFanToken.previewWithdraw(transferAmount));
        vm.startPrank(nonSponsor);
        bryanFanToken.sponsorTransfer(sponsor, transferAmount);

        uint256 finalNonSponsorShares = bryanFanToken.balanceOf(nonSponsor);
        uint256 finalSponsorAssets = bryanFanToken.balanceOfSponsorAssets(sponsor);
        uint256 expectedShares = bryanFanToken.previewWithdraw(transferAmount);

        console.log("After transfer (non-sponsor -> sponsor):");
        console.log("  Non-sponsor shares:", finalNonSponsorShares);
        console.log("  Sponsor assets:", finalSponsorAssets);
        console.log("  Expected shares:", expectedShares);

        assertEq(finalNonSponsorShares, nonSponsorShares - expectedShares, "non-sponsor shares should decrease");
        assertEq(finalSponsorAssets, transferAmount, "sponsor should receive assets");
    }

    function test_sponsorTransfer_from_nonsponsor_to_nonsponsor_reverts() public {
        address nonSponsor1 = makeAddr("nonSponsor1");
        address nonSponsor2 = makeAddr("nonSponsor2");

        // Set up first non-sponsor with assets
        (IERC4626 asset, uint256 assets) = _dealAsset(1 ether, address(this));
        require(asset.transfer(nonSponsor1, assets), "asset transfer failed");

        vm.startPrank(nonSponsor1);
        asset.approve(address(bryanFanToken), type(uint256).max);

        uint256 when = bryanFanToken.startDeposit(assets, nonSponsor1);
        if (when > 0) {
            vm.warp(when);
            bryanFanToken.deposit(assets, nonSponsor1);
        }

        uint256 transferAmount = bryanFanToken.previewRedeem(bryanFanToken.balanceOf(nonSponsor1) / 2);
        assertGt(transferAmount, 0, "transfer amount should be non-zero");

        // This should revert with AtLeastOneSideMustBeSponsor
        vm.expectRevert(AtLeastOneSideMustBeSponsor.selector);
        bryanFanToken.sponsorTransfer(nonSponsor2, transferAmount);
    }

    function test_harvestSponsorship_public_function() public {
        // Test that harvestSponsorship() can be called as a public function
        // This should typically return 0 when there's no excess shares to burn

        // Call harvestSponsorship directly as public function
        uint256 amount = bryanFanToken.harvestSponsorship();

        // Should return 0 when there are no excess shares
        assertEq(amount, 0, "harvestSponsorship should return 0 with no excess shares");
    }

    function test_withdraw_sponsor_with_approval() public {
        address withdrawer = makeAddr("withdrawer");

        // Set up sponsor with assets
        (IERC4626 asset, uint256 assets) = _dealAsset(2 ether, address(this));
        require(asset.transfer(sponsor, assets), "asset transfer failed");

        vm.startPrank(sponsor);
        bryanFanToken.setSponsorship(true);
        asset.approve(address(bryanFanToken), type(uint256).max);

        uint256 when = bryanFanToken.startDeposit(assets, sponsor);
        if (when > 0) {
            vm.warp(when);
            bryanFanToken.deposit(assets, sponsor);
        }

        uint256 sponsorAssets = bryanFanToken.balanceOfSponsorAssets(sponsor);
        uint256 withdrawAmount = sponsorAssets / 2;

        console.log("Before withdrawal:");
        console.log("  Sponsor assets:", sponsorAssets);
        console.log("  Sponsor direct balance:", bryanFanToken.balanceOf(sponsor));
        console.log("  Contract balance:", bryanFanToken.balanceOf(address(bryanFanToken)));

        // Approve withdrawer to withdraw sponsor's tokens
        uint256 sharesToApprove = bryanFanToken.previewWithdraw(withdrawAmount);
        bryanFanToken.approve(withdrawer, sharesToApprove);

        console.log("  Approved shares:", sharesToApprove);
        console.log("  Allowance:", bryanFanToken.allowance(sponsor, withdrawer));

        // Withdrawer tries to withdraw sponsor's tokens
        vm.startPrank(withdrawer);

        console.log("Attempting withdrawal by approved withdrawer...");
        // This should work but might fail due to approval logic issues
        uint256 withdrawn = bryanFanToken.withdraw(withdrawAmount, withdrawer, sponsor);

        console.log("After withdrawal:");
        console.log("  Withdrawn amount:", withdrawn);
        console.log("  Sponsor assets:", bryanFanToken.balanceOfSponsorAssets(sponsor));
        console.log("  Withdrawer received:", asset.balanceOf(withdrawer));

        assertEq(withdrawn, withdrawAmount, "should withdraw the requested amount");
        assertEq(
            bryanFanToken.balanceOfSponsorAssets(sponsor),
            sponsorAssets - withdrawAmount,
            "sponsor assets should decrease"
        );
    }

    function test_withdraw_sponsor_without_approval_should_fail() public {
        address withdrawer = makeAddr("withdrawer");

        // Set up sponsor with assets
        (IERC4626 asset, uint256 assets) = _dealAsset(1 ether, address(this));
        require(asset.transfer(sponsor, assets), "asset transfer failed");

        vm.startPrank(sponsor);
        bryanFanToken.setSponsorship(true);
        asset.approve(address(bryanFanToken), type(uint256).max);

        uint256 when = bryanFanToken.startDeposit(assets, sponsor);
        if (when > 0) {
            vm.warp(when);
            bryanFanToken.deposit(assets, sponsor);
        }

        uint256 sponsorAssets = bryanFanToken.balanceOfSponsorAssets(sponsor);
        uint256 withdrawAmount = sponsorAssets / 2;

        // Withdrawer tries to withdraw sponsor's tokens WITHOUT approval
        vm.startPrank(withdrawer);

        console.log("Attempting withdrawal without approval...");
        // This should fail with insufficient allowance
        vm.expectRevert(); // Should revert with ERC20InsufficientAllowance
        bryanFanToken.withdraw(withdrawAmount, withdrawer, sponsor);
    }

    function test_withdraw_non_sponsor() public {
        // Set up alice with assets
        (IERC4626 asset, uint256 assets) = _dealAsset(2 ether, alice);

        vm.startPrank(alice);
        asset.approve(address(bryanFanToken), type(uint256).max);

        uint256 when = bryanFanToken.startDeposit(assets, alice);
        if (when > 0) {
            vm.warp(when);
            bryanFanToken.deposit(assets, alice);
        }

        uint256 userShares = bryanFanToken.balanceOf(alice);
        uint256 withdrawAmount = bryanFanToken.convertToAssets(userShares / 2);

        console.log("Before withdrawal (non-sponsor):");
        console.log("  alice shares:", userShares);
        console.log("  Withdraw amount:", withdrawAmount);

        // alice withdraws their own tokens
        uint256 withdrawn = bryanFanToken.withdraw(withdrawAmount, alice, alice);

        console.log("After withdrawal (non-sponsor):");
        console.log("  Withdrawn amount:", withdrawn);
        console.log("  alice shares remaining:", bryanFanToken.balanceOf(alice));

        assertEq(withdrawn, withdrawAmount, "should withdraw the requested amount");
        assertLt(bryanFanToken.balanceOf(alice), userShares, "alice shares should decrease");
    }

    function test_withdraw_sponsor_self() public {
        // Set up sponsor with assets
        (IERC4626 asset, uint256 assets) = _dealAsset(2 ether, address(this));
        require(asset.transfer(sponsor, assets), "asset transfer failed");

        vm.startPrank(sponsor);
        bryanFanToken.setSponsorship(true);
        asset.approve(address(bryanFanToken), type(uint256).max);

        uint256 when = bryanFanToken.startDeposit(assets, sponsor);
        if (when > 0) {
            vm.warp(when);
            bryanFanToken.deposit(assets, sponsor);
        }

        uint256 sponsorAssets = bryanFanToken.balanceOfSponsorAssets(sponsor);
        uint256 withdrawAmount = sponsorAssets / 2;

        console.log("Before self-withdrawal (sponsor):");
        console.log("  Sponsor assets:", sponsorAssets);
        console.log("  Total sponsor assets:", bryanFanToken.totalSponsorAssets());

        // Sponsor withdraws their own tokens
        uint256 withdrawn = bryanFanToken.withdraw(withdrawAmount, sponsor, sponsor);

        console.log("After self-withdrawal (sponsor):");
        console.log("  Withdrawn amount:", withdrawn);
        console.log("  Sponsor assets:", bryanFanToken.balanceOfSponsorAssets(sponsor));
        console.log("  Total sponsor assets:", bryanFanToken.totalSponsorAssets());

        assertEq(withdrawn, withdrawAmount, "should withdraw the requested amount");
        assertEq(
            bryanFanToken.balanceOfSponsorAssets(sponsor),
            sponsorAssets - withdrawAmount,
            "sponsor assets should decrease"
        );
        assertEq(
            bryanFanToken.totalSponsorAssets(), sponsorAssets - withdrawAmount, "total sponsor assets should decrease"
        );
    }

    function test_withdraw_sponsor_insufficient_balance() public {
        // Set up sponsor with assets
        (IERC4626 asset, uint256 assets) = _dealAsset(1 ether, sponsor);

        vm.startPrank(sponsor);
        bryanFanToken.setSponsorship(true);
        asset.approve(address(bryanFanToken), type(uint256).max);

        uint256 when = bryanFanToken.startDeposit(assets, sponsor);
        if (when > 0) {
            vm.warp(when);
            bryanFanToken.deposit(assets, sponsor);
        }

        uint256 sponsorAssets = bryanFanToken.balanceOfSponsorAssets(sponsor);
        uint256 excessiveAmount = sponsorAssets + 1 ether;

        console.log("Attempting withdrawal of more than sponsor balance:");
        console.log("  Sponsor assets:", sponsorAssets);
        console.log("  Excessive amount:", excessiveAmount);

        // Should fail with InsufficientSponsorBalance
        uint256 excessiveShares = bryanFanToken.previewWithdraw(excessiveAmount);
        uint256 availableShares = bryanFanToken.previewWithdraw(sponsorAssets);
        vm.expectRevert(
            abi.encodeWithSelector(
                InsufficientSponsorBalance.selector,
                sponsor,
                sponsorAssets,
                availableShares,
                excessiveAmount,
                excessiveShares
            )
        );
        bryanFanToken.withdraw(excessiveAmount, sponsor, sponsor);
    }

    function test_redeem_sponsor() public {
        // Set up sponsor with assets
        (IERC4626 asset, uint256 assets) = _dealAsset(2 ether, sponsor);

        vm.startPrank(sponsor);
        bryanFanToken.setSponsorship(true);
        asset.approve(address(bryanFanToken), type(uint256).max);

        uint256 when = bryanFanToken.startDeposit(assets, sponsor);
        if (when > 0) {
            vm.warp(when);
            bryanFanToken.deposit(assets, sponsor);
        }

        uint256 sponsorAssets = bryanFanToken.balanceOfSponsorAssets(sponsor);
        uint256 sharesToRedeem = bryanFanToken.previewWithdraw(sponsorAssets / 2);
        assertEq(sharesToRedeem, 1 ether, "should calculate 1 ether of shares to redeem");

        console.log("Before redeem (sponsor):");
        console.log("  Sponsor assets:", sponsorAssets);
        console.log("  Shares to redeem:", sharesToRedeem);

        // Sponsor redeems shares
        uint256 redeemed = bryanFanToken.redeem(sharesToRedeem, sponsor, sponsor);

        console.log("After redeem (sponsor):");
        console.log("  Redeemed amount:", redeemed);
        console.log("  Sponsor assets:", bryanFanToken.balanceOfSponsorAssets(sponsor));

        assertEq(redeemed, sharesToRedeem, "should redeem the calculated shares amount");
        // redeem now properly updates sponsor accounting
        uint256 redeemedAssets = bryanFanToken.previewRedeem(sharesToRedeem);
        assertEq(
            bryanFanToken.balanceOfSponsorAssets(sponsor),
            sponsorAssets - redeemedAssets,
            "sponsor assets should decrease"
        );
    }

    function test_redeem_non_sponsor() public {
        // Set up alice with assets
        (IERC4626 asset, uint256 assets) = _dealAsset(1 ether, alice);

        vm.startPrank(alice);
        asset.approve(address(bryanFanToken), type(uint256).max);

        uint256 when = bryanFanToken.startDeposit(assets, alice);
        if (when > 0) {
            vm.warp(when);
            bryanFanToken.deposit(assets, alice);
        }

        uint256 userShares = bryanFanToken.balanceOf(alice);
        uint256 sharesToRedeem = userShares / 2;
        assertEq(sharesToRedeem, 0.5 ether, "should calculate 0.5 ether of shares to redeem");

        console.log("Before redeem (non-sponsor):");
        console.log("  alice shares:", userShares);
        console.log("  Shares to redeem:", sharesToRedeem);

        // alice redeems shares
        uint256 assetsRedeemed = bryanFanToken.redeem(sharesToRedeem, alice, alice);

        console.log("After redeem (non-sponsor):");
        console.log("  Redeemed assets:", assetsRedeemed);
        console.log("  alice shares remaining:", bryanFanToken.balanceOf(alice));

        // TODO: shares are 1:1. that makes these asserts feel fragile
        assertEq(assetsRedeemed, 0.5 ether, "should redeem the calculated shares amount");
        assertEq(bryanFanToken.balanceOf(alice), userShares - sharesToRedeem, "alice shares should decrease");
    }

    function test_redeem_insufficient_balance_sponsor() public {
        (IERC4626 asset, uint256 assets) = _dealAsset(1 ether, sponsor);

        vm.startPrank(sponsor);
        bryanFanToken.setSponsorship(true);
        asset.approve(address(bryanFanToken), type(uint256).max);

        uint256 when = bryanFanToken.startDeposit(assets, sponsor);
        if (when > 0) {
            vm.warp(when);
            bryanFanToken.deposit(assets, sponsor);
        }

        uint256 sponsorAssets = bryanFanToken.balanceOfSponsorAssets(sponsor);
        uint256 maxShares = bryanFanToken.previewWithdraw(sponsorAssets);
        uint256 excessiveShares = maxShares + 1e18;

        console.log("Attempting redeem of more than sponsor shares:");
        console.log("  Sponsor assets:", sponsorAssets);
        console.log("  Max redeemable shares:", maxShares);
        console.log("  Excessive shares:", excessiveShares);

        // Should fail with InsufficientSponsorBalance
        uint256 excessiveAssets = bryanFanToken.previewRedeem(excessiveShares);
        uint256 availableShares = bryanFanToken.previewWithdraw(sponsorAssets);
        vm.expectRevert(
            abi.encodeWithSelector(
                InsufficientSponsorBalance.selector,
                sponsor,
                sponsorAssets,
                availableShares,
                excessiveAssets,
                excessiveShares
            )
        );
        bryanFanToken.redeem(excessiveShares, sponsor, sponsor);
    }

    function test_withdraw_with_allowance() public {
        address withdrawer = makeAddr("withdrawer");

        // Set up alice with assets
        (IERC4626 asset, uint256 assets) = _dealAsset(1 ether, address(this));
        require(asset.transfer(alice, assets), "asset transfer failed");

        vm.startPrank(alice);
        asset.approve(address(bryanFanToken), type(uint256).max);

        uint256 when = bryanFanToken.startDeposit(assets, alice);
        if (when > 0) {
            vm.warp(when);
            bryanFanToken.deposit(assets, alice);
        }

        uint256 userShares = bryanFanToken.balanceOf(alice);
        uint256 withdrawAmount = bryanFanToken.convertToAssets(userShares / 2);
        uint256 sharesToApprove = bryanFanToken.previewWithdraw(withdrawAmount);

        // Approve withdrawer
        bryanFanToken.approve(withdrawer, sharesToApprove);

        // Withdrawer withdraws alice's tokens
        vm.startPrank(withdrawer);

        uint256 withdrawn = bryanFanToken.withdraw(withdrawAmount, withdrawer, alice);

        assertEq(withdrawn, withdrawAmount, "should withdraw the requested amount");
        assertEq(bryanFanToken.balanceOf(alice), userShares - sharesToApprove, "alice shares should decrease");
        assertEq(bryanFanToken.allowance(alice, withdrawer), 0, "allowance should be consumed");
    }

    // ============ INVARIANT TESTS ============
    // Tests for critical invariants and logical correctness

    function test_sponsor_accounting_invariant() public {
        // Setup multiple sponsors with different amounts
        (IERC4626 asset, uint256 assets1) = _dealAsset(5 ether, sponsor1);
        (, uint256 assets2) = _dealAsset(3 ether, sponsor2);
        (, uint256 assets3) = _dealAsset(2 ether, sponsor3);

        // All become sponsors and deposit
        address[] memory sponsors = new address[](3);
        uint256[] memory amounts = new uint256[](3);
        sponsors[0] = sponsor1;
        amounts[0] = assets1;
        sponsors[1] = sponsor2;
        amounts[1] = assets2;
        sponsors[2] = sponsor3;
        amounts[2] = assets3;

        for (uint256 i = 0; i < 3; i++) {
            vm.startPrank(sponsors[i]);
            asset.approve(address(bryanFanToken), type(uint256).max);
            uint256 when = bryanFanToken.startDeposit(amounts[i], sponsors[i]);
            if (when > 0) {
                vm.warp(when);
                bryanFanToken.finishDeposit(sponsors[i], sponsors[i]);
            }
        }

        // Check invariant: totalSponsorAssets = sum of individual balances
        _checkSponsorAccountingInvariant(sponsors);

        // Perform various operations and check invariant holds
        vm.startPrank(sponsor1);
        bryanFanToken.sponsorTransfer(sponsor2, 1 ether);
        _checkSponsorAccountingInvariant(sponsors);

        vm.startPrank(sponsor2);
        bryanFanToken.sponsorBurn(0.5 ether);
        _checkSponsorAccountingInvariant(sponsors);

        vm.startPrank(sponsor3);
        bryanFanToken.setSponsorship(false);
        _checkSponsorAccountingInvariant(sponsors);
    }

    function _checkSponsorAccountingInvariant(address[] memory sponsors) internal view {
        uint256 sumIndividual = 0;
        for (uint256 i = 0; i < sponsors.length; i++) {
            sumIndividual += bryanFanToken.balanceOfSponsorAssets(sponsors[i]);
        }

        uint256 totalReported = bryanFanToken.totalSponsorAssets();
        assertEq(totalReported, sumIndividual, "totalSponsorAssets must equal sum of individual balanceOfSponsorAssets");
    }

    /// TODO: rewrite this ai slop
    function test_withdraw_sponsor_boundaries() public {
        (IERC4626 asset, uint256 totalAssets) = _dealAsset(10 ether, sponsor);

        vm.startPrank(sponsor);
        bryanFanToken.setSponsorship(true);
        asset.approve(address(bryanFanToken), type(uint256).max);
        uint256 when = bryanFanToken.startDeposit(totalAssets, sponsor);
        if (when > 0) {
            vm.warp(when);
            bryanFanToken.finishDeposit(sponsor, sponsor);
        }

        uint256 sponsorBalance = bryanFanToken.balanceOfSponsorAssets(sponsor);
        assertEq(sponsorBalance, totalAssets, "Sponsor balance should equal deposited assets");

        // Test exact balance withdrawal
        uint256 withdrawn1 = bryanFanToken.withdraw(sponsorBalance, sponsor, sponsor);
        assertEq(withdrawn1, sponsorBalance, "Should withdraw exact sponsor balance");
        assertEq(
            bryanFanToken.balanceOfSponsorAssets(sponsor), 0, "Sponsor balance should be zero after full withdrawal"
        );

        // Deposit again for next test
        uint256 when2 = bryanFanToken.startDeposit(totalAssets, sponsor);
        if (when2 > 0) {
            vm.warp(when2);
            bryanFanToken.finishDeposit(sponsor, sponsor);
        }

        // Test withdrawal that exceeds balance should revert
        uint256 excessiveAmount = bryanFanToken.balanceOfSponsorAssets(sponsor) + 1;
        uint256 availableShares = bryanFanToken.previewWithdraw(bryanFanToken.balanceOfSponsorAssets(sponsor));
        uint256 excessiveShares = bryanFanToken.previewWithdraw(excessiveAmount);

        vm.expectRevert(
            abi.encodeWithSelector(
                InsufficientSponsorBalance.selector,
                sponsor,
                bryanFanToken.balanceOfSponsorAssets(sponsor),
                availableShares,
                excessiveAmount,
                excessiveShares
            )
        );
        bryanFanToken.withdraw(excessiveAmount, sponsor, sponsor);
    }

    function test_deposit_delay_timing() public {
        (IERC4626 asset, uint256 assets1) = _dealAsset(1 ether, alice);
        (, uint256 assets2) = _dealAsset(1 ether, bob);

        // First deposit should have no delay (totalSupply == 0)
        vm.startPrank(alice);
        asset.approve(address(bryanFanToken), type(uint256).max);
        uint256 claimWhen1 = bryanFanToken.startDeposit(assets1, alice);
        assertEq(claimWhen1, 0, "First deposit should have no delay");

        uint256 shares1 = bryanFanToken.balanceOf(alice);
        assertEq(shares1, assets1, "Should receive shares equal to deposited assets for first deposit");

        // Second deposit should have delay (totalSupply > 0)
        vm.startPrank(bob);
        asset.approve(address(bryanFanToken), type(uint256).max);

        uint256 startTime = block.timestamp;
        uint256 expectedDelay = bryanFanToken.DEPOSIT_DELAY();
        uint256 claimWhen2 = bryanFanToken.startDeposit(assets2, bob);

        assertEq(claimWhen2, startTime + expectedDelay, "Second deposit claim time calculation incorrect");

        // Should not be able to finalize before delay
        vm.expectRevert(abi.encodeWithSelector(DepositNotReady.selector));
        bryanFanToken.finishDeposit(bob, bob);

        // Should be able to finalize exactly at delay time
        vm.warp(claimWhen2);
        uint256 shares2 = bryanFanToken.finishDeposit(bob, bob);
        assertEq(shares2, assets2, "Should receive shares equal to deposited assets after delay");
    }

    /// TODO: rewrite this ai slop
    function test_sponsorTransfer_multiple_scenarios() public {
        (IERC4626 asset, uint256 assets) = _dealAsset(5 ether, sponsor1);
        (, uint256 assets2) = _dealAsset(3 ether, nonSponsor);

        // Setup sponsor1
        vm.startPrank(sponsor1);
        bryanFanToken.setSponsorship(true);
        asset.approve(address(bryanFanToken), type(uint256).max);
        uint256 when1 = bryanFanToken.startDeposit(assets, sponsor1);
        if (when1 > 0) {
            vm.warp(when1);
            bryanFanToken.finishDeposit(sponsor1, sponsor1);
        }

        // Setup nonSponsor (must wait for delay since sponsor1 already deposited)
        vm.startPrank(nonSponsor);
        asset.approve(address(bryanFanToken), type(uint256).max);
        uint256 when2 = bryanFanToken.startDeposit(assets2, nonSponsor);
        if (when2 > 0) {
            vm.warp(when2);
            bryanFanToken.finishDeposit(nonSponsor, nonSponsor);
        }

        // Setup sponsor2 (empty initially)
        vm.startPrank(sponsor2);
        bryanFanToken.setSponsorship(true);

        uint256 transferAmount = 1 ether;

        // Test sponsor-to-sponsor transfer
        vm.startPrank(sponsor1);
        bryanFanToken.sponsorTransfer(sponsor2, transferAmount);

        assertEq(
            bryanFanToken.balanceOfSponsorAssets(sponsor1),
            assets - transferAmount,
            "Sponsor1 balance incorrect after transfer"
        );
        assertEq(
            bryanFanToken.balanceOfSponsorAssets(sponsor2), transferAmount, "Sponsor2 balance incorrect after transfer"
        );

        // Total should remain unchanged
        assertEq(bryanFanToken.totalSponsorAssets(), assets, "Total sponsor assets should remain constant");

        // Test non-sponsor to sponsor transfer (should convert shares)
        uint256 nonSponsorShares = bryanFanToken.balanceOf(nonSponsor);
        uint256 nonSponsorAssets = bryanFanToken.convertToAssets(nonSponsorShares);

        vm.startPrank(nonSponsor);
        bryanFanToken.sponsorTransfer(sponsor1, nonSponsorAssets);

        // Non-sponsor should lose all shares
        assertEq(bryanFanToken.balanceOf(nonSponsor), 0, "Non-sponsor should have no shares left");

        // Sponsor should gain the assets
        assertEq(
            bryanFanToken.balanceOfSponsorAssets(sponsor1),
            assets - transferAmount + nonSponsorAssets,
            "Sponsor1 balance incorrect after receiving from non-sponsor"
        );
    }
}
