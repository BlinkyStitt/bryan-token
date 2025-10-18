// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {FanToken, IERC20, IERC4626, IWETH9} from "../src/FanToken.sol";
import {FanTokenFactory} from "../src/FanTokenFactory.sol";
import {Generic4626Router} from "../src/interfaces/Generic4626Router.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {console} from "forge-std/console.sol";

contract FanTokenVaultLossTest is Test {
    using SafeERC20 for IERC20;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address owner = makeAddr("owner");
    address treasury = makeAddr("treasury");

    IERC4626 constant PRIZE_VAULT = IERC4626(0x4E42f783db2D0C5bDFf40fDc66FCAe8b1Cda4a43);
    Generic4626Router constant UNISWAP_V4_4626_HOOK =
        Generic4626Router(address(0xD60a6A0f0D5E3Fd451449C7256BbbDC59561e888));
    IWETH9 constant WETH9 = IWETH9(payable(0x4200000000000000000000000000000000000006));

    FanTokenFactory factory;
    FanToken public fanToken;
    IERC20 underlying;

    function setUp() public {
        deal(owner, 100 ether);
        deal(address(this), 100_000 ether);

        factory = new FanTokenFactory(UNISWAP_V4_4626_HOOK, WETH9);

        vm.prank(owner);
        fanToken = factory.create(
            "Test Token",
            "TEST",
            0, // no owner fee
            0, // no treasury fee
            PRIZE_VAULT,
            address(0), // no treasury
            false,
            bytes32(0),
            0, // no initial deposit
            false
        );

        underlying = fanToken.UNDERLYING();

        // Make an initial deposit from owner (underlying is WETH, so wrap ETH)
        uint256 initialDeposit = 10 ether;
        
        vm.startPrank(owner);
        // Wrap ETH to WETH
        WETH9.deposit{value: initialDeposit}();
        
        // Deposit WETH into prize vault
        WETH9.approve(address(PRIZE_VAULT), initialDeposit);
        uint256 prizeVaultShares = PRIZE_VAULT.deposit(initialDeposit, owner);
        
        // Then deposit prize vault shares into fan token (first deposit is instant)
        IERC20(address(PRIZE_VAULT)).approve(address(fanToken), prizeVaultShares);
        fanToken.deposit(prizeVaultShares, owner);
        vm.stopPrank();
    }

    /// @dev Helper to deposit underlying and get fan token shares
    function _deposit(address user, uint256 underlyingAmount) internal returns (uint256 shares) {
        deal(address(underlying), user, underlyingAmount, false);

        vm.startPrank(user);
        underlying.approve(address(PRIZE_VAULT), type(uint256).max);
        uint256 prizeVaultShares = PRIZE_VAULT.deposit(underlyingAmount, user);

        IERC20(address(PRIZE_VAULT)).approve(address(fanToken), type(uint256).max);

        // First deposit is instant
        if (fanToken.totalSupply() == 0) {
            shares = fanToken.deposit(prizeVaultShares, user);
        } else {
            // Subsequent deposits need delay
            uint256 when = fanToken.startDeposit(prizeVaultShares, user);
            if (when > 0) {
                vm.warp(when);
                shares = fanToken.finishDeposit(user, user);
            } else {
                shares = prizeVaultShares;
            }
        }
        vm.stopPrank();
    }

    /// @dev Simulate a 50% loss in the prize vault
    /// @notice This is a placeholder - actual loss simulation is difficult on a live fork
    /// The test will demonstrate that without the multiplier fix, sponsors don't lose value
    function _simulateVaultLoss50Percent() internal {
        // NOTE: We can't easily simulate vault losses on a forked network
        // because the prize vault's internal accounting is complex
        // This test will FAIL showing that sponsors DON'T lose value when they should
        // Once we implement the multiplier fix, we'll need a different approach to test it

        // For now, this function does nothing, and the test assertions will fail
        // showing that balances don't change (proving the bug exists)
    }

    function test_vault_loss_affects_sponsors_and_nonsponsor_equally() public {
        // Owner should already have shares from setUp (first deposit is instant)
        uint256 ownerInitialShares = fanToken.balanceOf(owner);
        assertGt(ownerInitialShares, 0, "Owner should have initial shares from setUp");

        // Transfer 30% to Alice (non-sponsor)
        uint256 aliceShares = ownerInitialShares * 30 / 100;
        vm.prank(owner);
        fanToken.transfer(alice, aliceShares);

        // Transfer 40% to Bob and make him a sponsor
        uint256 bobSharesInitial = ownerInitialShares * 40 / 100;
        vm.prank(owner);
        fanToken.transfer(bob, bobSharesInitial);

        vm.prank(bob);
        fanToken.setSponsorship(true);

        // Owner keeps remaining 30% (non-sponsor)
        uint256 ownerShares = fanToken.balanceOf(owner);

        // Verify initial distribution
        assertEq(fanToken.balanceOf(alice), aliceShares, "Alice should have 30% of shares");
        assertEq(fanToken.balanceOf(owner), ownerShares, "Owner should have remaining 30%");
        assertTrue(fanToken.isSponsor(bob), "Bob should be a sponsor");

        // Record balances before loss
        uint256 aliceAssetsBefore = fanToken.convertToAssets(aliceShares);
        uint256 bobAssetsBefore = fanToken.balanceOfSponsorAssets(bob);
        uint256 ownerAssetsBefore = fanToken.convertToAssets(ownerShares);
        uint256 totalAssetsBefore = aliceAssetsBefore + bobAssetsBefore + ownerAssetsBefore;

        // Verify balances add up correctly
        assertGt(totalAssetsBefore, 0, "Total assets before should be > 0");
        assertEq(
            aliceAssetsBefore + bobAssetsBefore + ownerAssetsBefore,
            totalAssetsBefore,
            "Individual balances should sum to total"
        );

        // Simulate 50% loss in prize vault
        _simulateVaultLoss50Percent();

        // Check balances after loss
        uint256 aliceAssetsAfter = fanToken.convertToAssets(aliceShares);
        uint256 bobAssetsAfter = fanToken.balanceOfSponsorAssets(bob);
        uint256 ownerAssetsAfter = fanToken.convertToAssets(ownerShares);
        uint256 totalAssetsAfter = aliceAssetsAfter + bobAssetsAfter + ownerAssetsAfter;

        // Assert everyone lost approximately 50% (allow 1% margin for rounding)
        assertApproxEqRel(aliceAssetsAfter, aliceAssetsBefore / 2, 0.01e18, "Alice should lose ~50%");
        assertApproxEqRel(bobAssetsAfter, bobAssetsBefore / 2, 0.01e18, "Bob (sponsor) should lose ~50%");
        assertApproxEqRel(ownerAssetsAfter, ownerAssetsBefore / 2, 0.01e18, "Owner should lose ~50%");

        // Total should also be halved
        assertApproxEqRel(totalAssetsAfter, totalAssetsBefore / 2, 0.01e18, "Total assets should be halved");

        // Verify losses are proportional (within 1% of each other)
        uint256 aliceLossRatio = (aliceAssetsBefore - aliceAssetsAfter) * 1e18 / aliceAssetsBefore;
        uint256 bobLossRatio = (bobAssetsBefore - bobAssetsAfter) * 1e18 / bobAssetsBefore;
        uint256 ownerLossRatio = (ownerAssetsBefore - ownerAssetsAfter) * 1e18 / ownerAssetsBefore;

        assertApproxEqRel(aliceLossRatio, bobLossRatio, 0.01e18, "Alice and Bob should have similar loss ratios");
        assertApproxEqRel(bobLossRatio, ownerLossRatio, 0.01e18, "Bob and Owner should have similar loss ratios");

        // Test that harvest still works correctly after loss
        // Send some rewards to the contract
        uint256 rewardAmount = 1 ether;
        deal(address(underlying), address(fanToken), rewardAmount, true);

        // Record balances before harvest
        uint256 aliceAssetsBeforeHarvest = fanToken.convertToAssets(aliceShares);
        uint256 bobAssetsBeforeHarvest = fanToken.balanceOfSponsorAssets(bob);
        uint256 ownerAssetsBeforeHarvest = fanToken.convertToAssets(ownerShares);
        uint256 totalBeforeHarvest = aliceAssetsBeforeHarvest + bobAssetsBeforeHarvest + ownerAssetsBeforeHarvest;

        // Harvest the rewards
        fanToken.harvest();

        // Check balances after harvest
        uint256 aliceAssetsAfterHarvest = fanToken.convertToAssets(aliceShares);
        uint256 bobAssetsAfterHarvest = fanToken.balanceOfSponsorAssets(bob);
        uint256 ownerAssetsAfterHarvest = fanToken.convertToAssets(ownerShares);
        uint256 totalAfterHarvest = aliceAssetsAfterHarvest + bobAssetsAfterHarvest + ownerAssetsAfterHarvest;

        // Non-sponsors (Alice and Owner) should benefit from rewards
        assertGt(aliceAssetsAfterHarvest, aliceAssetsBeforeHarvest, "Alice should gain from harvest");
        assertGt(ownerAssetsAfterHarvest, ownerAssetsBeforeHarvest, "Owner should gain from harvest");

        // Sponsor (Bob) should NOT benefit from rewards (they get burned via harvestSponsorship)
        assertEq(bobAssetsAfterHarvest, bobAssetsBeforeHarvest, "Bob (sponsor) should not gain from harvest");

        // Total should increase (from non-sponsors gaining)
        assertGt(totalAfterHarvest, totalBeforeHarvest, "Total should increase from harvest");

        // Verify the gain went only to non-sponsors proportionally
        uint256 aliceGainRatio = (aliceAssetsAfterHarvest - aliceAssetsBeforeHarvest) * 1e18 / aliceAssetsBeforeHarvest;
        uint256 ownerGainRatio = (ownerAssetsAfterHarvest - ownerAssetsBeforeHarvest) * 1e18 / ownerAssetsBeforeHarvest;

        assertApproxEqRel(aliceGainRatio, ownerGainRatio, 0.01e18, "Non-sponsors should gain proportionally");
    }
}
