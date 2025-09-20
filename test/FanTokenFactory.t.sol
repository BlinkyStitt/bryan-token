// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {FanToken, FanTokenFactory, IERC20, IERC4626, IWETH9} from "../src/FanTokenFactory.sol";
import {console} from "forge-std/console.sol";

contract FanTokenFactoryTest is Test {
    IERC4626 prizeVault;
    FanToken public bryan;
    FanTokenFactory public fanTokenFactory;

    address treasury;
    IWETH9 weth;

    function setUp() public {
        weth = IWETH9(address(0x4200000000000000000000000000000000000006));

        fanTokenFactory = new FanTokenFactory(weth);

        // TODO: use flags on the test command instead of forcing a fork here?
        address owner = makeAddr("bryan owner");

        prizeVault = IERC4626(0x4E42f783db2D0C5bDFf40fDc66FCAe8b1Cda4a43);

        // TODO: need tests that have fees!
        uint256 harvestOwnerFeeBasisPoints = 0;
        uint256 harvestTreasuryFeeBasisPoints = 0;
        treasury = makeAddr("treasury");
        uint256 initialDeposit = 0 ether;

        bytes32 salt = bytes32(0);

        vm.prank(owner);
        bryan = fanTokenFactory.create(
            "ETH from Bryan",
            "BRY-ETH",
            harvestOwnerFeeBasisPoints,
            harvestTreasuryFeeBasisPoints,
            prizeVault,
            treasury,
            salt,
            initialDeposit
        );
    }

    function test_initial_deposit() public {
        uint256 initialDeposit = 1 ether;

        FanToken fanToken = fanTokenFactory.create{value: initialDeposit}(
            "ETH from Bryan Again", "BRY-ETH-2", 0, 0, prizeVault, address(0), bytes32(0), initialDeposit
        );

        uint256 initialShares = fanToken.previewWithdraw(initialDeposit);
        console.log("initial shares:", initialShares);

        assertEq(fanToken.balanceOfSponsor(address(this)), initialDeposit, "initial deposits should be 1:1");

        assertEq(fanToken.balanceOf(address(fanToken)), initialShares, "the contract should own the sponsored shares");

        // TODO: i can't decide if we should override balanceOf to include sponsor tokens. that will make transfers easy, but i think has other problems
        assertEq(fanToken.balanceOf(address(this)), 0, "there should be some initial shares");

        // TODO: what should the value of this actually be?
    }

    function test_vault_asset() public view {
        require(address(bryan.UNDERLYING()) == address(weth));
    }

    function test_factory_payable_deposit() public {
        uint256 underlyingAssets = 1 ether;

        deal(address(this), underlyingAssets);

        address receiver = makeAddr("receiver");

        // TODO: this is the first call to startDeposit for this contract. we need to
        uint256 when = fanTokenFactory.startDeposit{value: underlyingAssets}(bryan, underlyingAssets, receiver);

        assertEq(when, 0, "first deposit should be instant");

        prizeVault = IERC4626(bryan.asset());

        // TODO: what should the amounts actually be?
        assertGt(bryan.balanceOf(receiver), 0, "receiver should have a balance");
        assertGt(prizeVault.balanceOf(address(bryan)), 0, "token should have a balance");

        // TODO: test fees! I want this fee to be sent as bryan, not as prizeVault!
        // assertGt(prizeVault.balanceOf(bryan.owner()), 0);
    }

    function test_factory_deposit_and_withdraw() public {
        address alice = makeAddr("alice");
        vm.startPrank(alice);

        // TODO: for some reason we can't deal the ERC4626. We can deal the ERC20 though.
        uint256 underlyingAssets = 1 ether;

        IERC20 underlying = bryan.UNDERLYING();
        deal(address(underlying), alice, underlyingAssets, false);

        // test the factory's deposit function
        underlying.approve(address(fanTokenFactory), type(uint256).max);
        uint256 when = fanTokenFactory.startDeposit(bryan, underlyingAssets, alice);
        assertEq(when, 0, "first deposit should be instant");

        IERC4626 asset = IERC4626(bryan.asset());
        uint256 shares = bryan.balanceOf(alice);
        console.log("shares:", shares);

        uint256 assets = bryan.previewRedeem(shares);
        console.log("assets:", assets);

        // TODO: check against a specific value
        assertGt(assets, 0, "no assets redeemed");

        // TODO: the fees make this annoying. TODO: I'm also not sure these are even the right checks. think about these more
        assertGt(asset.balanceOf(address(bryan)), 0, "asset balance does not match assets");

        // test the main redeem function
        // TODO: send to a "receiver" address just to make the accounting clean?
        bryan.approve(address(fanTokenFactory), type(uint256).max);
        uint256 redeemed = fanTokenFactory.redeem(bryan, shares, address(alice));
        console.log("redeemed:", redeemed);

        // TODO: the fees make this annoying. TODO: I'm also not sure these are even the right checks. think about these more
        assertGt(redeemed, 0, "none redeemed"); // TODO: what should this amount be?
        assertEq(underlying.balanceOf(address(alice)), underlyingAssets, "we should have our asset back");
        assertEq(IERC20(bryan.asset()).balanceOf(address(bryan)), 0, "token's asset balance should be empty");
        assertEq(bryan.balanceOf(address(alice)), 0, "our balance of bryan should be empty");
    }

    function test_enumeration_functions() public {
        // Get initial count (should include the bryan token from setUp)
        uint256 initialCount = fanTokenFactory.getDeployedTokenCount();

        // Verify the bryan token is in the set
        assertTrue(fanTokenFactory.isDeployed(address(bryan)), "bryan token should be deployed");

        // Initial getAllDeployedTokens should include bryan
        address[] memory initialTokens = fanTokenFactory.getAllDeployedTokens();
        assertEq(initialTokens.length, initialCount, "initial token count should match");

        // Create first new token
        FanToken token1 = fanTokenFactory.create(
            "Token 1",
            "TK1",
            0,
            0,
            prizeVault,
            address(0),
            bytes32(uint256(1)),
            0
        );

        // Verify count increased
        assertEq(fanTokenFactory.getDeployedTokenCount(), initialCount + 1, "count should increase by 1");

        // Verify token is marked as deployed
        assertTrue(fanTokenFactory.isDeployed(address(token1)), "token1 should be deployed");
        assertFalse(fanTokenFactory.isDeployed(address(0x123)), "random address should not be deployed");

        // Verify we can get it by index
        assertEq(fanTokenFactory.getDeployedTokenAt(initialCount), address(token1), "should get token1 at new index");

        // Create second token
        FanToken token2 = fanTokenFactory.create(
            "Token 2",
            "TK2",
            0,
            0,
            prizeVault,
            address(0),
            bytes32(uint256(2)),
            0
        );

        // Test final state
        assertEq(fanTokenFactory.getDeployedTokenCount(), initialCount + 2, "should have 2 more tokens");
        assertTrue(fanTokenFactory.isDeployed(address(token2)), "token2 should be deployed");
        assertEq(fanTokenFactory.getDeployedTokenAt(initialCount + 1), address(token2), "should get token2 at index");

        // Test getAllDeployedTokens
        address[] memory allTokens = fanTokenFactory.getAllDeployedTokens();
        assertEq(allTokens.length, initialCount + 2, "should return all tokens");
        assertEq(allTokens[initialCount], address(token1), "token1 should be at correct position");
        assertEq(allTokens[initialCount + 1], address(token2), "token2 should be at correct position");

        // Test pagination - get just the new tokens
        address[] memory newTokens = fanTokenFactory.getDeployedTokens(initialCount, initialCount + 2);
        assertEq(newTokens.length, 2, "pagination should return 2 tokens");
        assertEq(newTokens[0], address(token1), "first new token should be token1");
        assertEq(newTokens[1], address(token2), "second new token should be token2");

        // Test single token pagination
        address[] memory singleToken = fanTokenFactory.getDeployedTokens(initialCount, initialCount + 1);
        assertEq(singleToken.length, 1, "single token pagination should return 1");
        assertEq(singleToken[0], address(token1), "should return token1");

        // Test empty pagination
        address[] memory emptyRange = fanTokenFactory.getDeployedTokens(initialCount + 2, initialCount + 2);
        assertEq(emptyRange.length, 0, "empty range should return empty array");
    }
}
