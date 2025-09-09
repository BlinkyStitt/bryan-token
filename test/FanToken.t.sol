// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {InvalidAuctionToken, FanToken, IERC20, IERC4626, IWETH9} from "../src/FanToken.sol";
import {Auction} from "../src/forks/AuctionSwapper.sol";
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
        assertEq(shares, assets / 2, "initial deposit failed");

        assertEq(bryan.totalSupply(), shares, "supply wrong 1");

        // todo: deposit without calling start should revert
        uint256 when = bryan.startDeposit(assets / 2, address(this));
        assertEq(when, block.timestamp + depositDelay, "startDeposit failed");
        assertEq(bryan.balanceOfPending(address(this)), assets / 2, "finishing deposit failed");

        assertEq(bryan.totalSupply(), shares, "supply wrong 2");

        vm.warp(block.timestamp + depositDelay);
        // TODO: test depositing from another address. anyone should be able to finalize a deposit
        uint256 newShares = bryan.deposit(assets / 2, address(this));

        assertEq(bryan.balanceOfPending(address(this)), 0, "finishing deposit failed");

        assertEq(bryan.totalSupply(), shares + newShares, "supply wrong 3");

        // TODO: the fees make this annoying
        // TODO: make sure that the balance of the prize vault grew by the underlying assets
        assertEq(asset.balanceOf(address(bryan)), assets, "asset balance does not match assets");
        assertEq(bryan.balanceOf(address(this)), shares + newShares, "bryan balance does not match shares");
        assertEq(bryan.balanceOfUnderlying(address(this)), underlyingAssets, "underlying balance does not match");

        // test the main redeem function
        uint256 redeemed = bryan.redeem(shares + newShares, address(this), address(this));

        assertGt(redeemed, 0, "none redeemed"); // TODO: what should this amount be?
        assertEq(IERC20(bryan.asset()).balanceOf(address(bryan)), 0, "token's asset balance should be empty");
        assertEq(bryan.balanceOf(address(this)), 0, "our balance of bryan should be empty");
        assertEq(asset.balanceOf(address(this)), assets, "we should have our asset back less the fee");
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
        IERC20 from = IERC20(0xd652C5425aea2Afd5fb142e120FeCf79e18fafc3); // POOL

        bytes32 auctionId = bryan.enableAuction(from);

        uint256 fromAmount = 1 ether;
        console.log("fromAmount", fromAmount);

        deal(address(from), address(bryan), fromAmount, true);

        assertEq(bryan.kickable(address(from)), fromAmount, "kickable amount wrong");

        Auction auction = Auction(bryan.auction());
        require(address(auction) != address(0), "no auction contract");

        // TODO: do we need to call approve here?
        uint256 available = auction.kick(auctionId);

        assertEq(fromAmount, available, "auction size incorrect");

        vm.warp(block.timestamp + 12 hours);

        uint256 wantAmount = auction.getAmountNeeded(auctionId, fromAmount);
        console.log("wantAmount", wantAmount);
        assertGt(wantAmount, 0, "want amount should be nonzero");

        address want = auction.want();
        console.log("want", want);
        assertEq(want, address(bryan.underlying()), "wrong want");

        // cheat to have the necessary tokens to fulfill the auction
        weth.deposit{value: wantAmount}();

        IERC20(want).approve(address(auction), wantAmount);
        uint256 amountFromTaken = auction.take(auctionId);
        console.log("amountFromTaken", want);

        assertEq(amountFromTaken, fromAmount, "from amount error");

        // thanks to the post take hook, this was deposited
        assertEq(IERC20(want).balanceOf(address(bryan)), 0);

        // TODO: i don't like this amount being hard coded.
        assertEq(IERC20(bryan.asset()).balanceOf(address(bryan)), 244140625000000000000);

        // TODO: check that the weth balances increased correctly
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
