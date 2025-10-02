// SPDX-License-Identifier: UNLICENSED
// script to deploy the tokens for Bryan. TODO: make this configurable so anyone can use it
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";
import {LibString} from "solady/utils/LibString.sol";
import {Script} from "forge-std/Script.sol";
import {FanToken} from "../src/FanTokenFactory.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {PrizePoolTwabRewards} from "../src/interfaces/PrizePoolTwabRewards.sol";

// TODO: rewrite this to prompt the user for inputs instead of having everything hard coded
contract ManageBryanScript is Script {
    using LibString for uint256;

    // these are the addresses on Base. Maybe these should be from config, but this is enough for me for now
    PrizePoolTwabRewards constant PRIZE_POOL_TWAB_REWARDS =
        PrizePoolTwabRewards(0xF4c47dacFda99bE38793181af9Fd1A2Ec7576bBF);

    IERC20Metadata public poolToken;

    FanToken public fanTokenUSDC;
    FanToken public fanTokenWETH;

    function setUp() public {
        // Read factory address from deployment artifacts for current chain
        // TODO: I'm not sure I like this. it should maybe read the addresses from a list saved somewhere instead?
        string memory chainId = vm.toString(block.chainid);
        string memory path = string.concat("./broadcast/CreateBryan.s.sol/", chainId, "/run-latest.json");
        string memory json = vm.readFile(path);

        // TODO: use filters to find the right transaction
        // 0 and 2 are probably approvals if this is the very first setup, but approvals might be done separately
        address fanTokenUSDCAddr = vm.parseJsonAddress(json, ".transactions[1].contractAddress");
        address fanTokenWETHAddr = vm.parseJsonAddress(json, ".transactions[3].contractAddress");

        fanTokenUSDC = FanToken(payable(fanTokenUSDCAddr));
        fanTokenWETH = FanToken(payable(fanTokenWETHAddr));

        // TODO: get this from PRIZE_POOL_TWAB_REWARDS?
        poolToken = IERC20Metadata(0xd652C5425aea2Afd5fb142e120FeCf79e18fafc3);
    }

    function run() public {
        IERC20Metadata weth = IERC20Metadata(fanTokenWETH.asset());
        IERC20Metadata usdc = IERC20Metadata(fanTokenUSDC.asset());

        // TODO: what should the minimums be?

        // usdc fan token
        claimPool(fanTokenUSDC, 10 * 10 ** usdc.decimals());
        kickAuction(fanTokenUSDC, poolToken, 10 ** poolToken.decimals());
        kickAuction(fanTokenUSDC, weth, 0.001 ether);
        harvest(fanTokenUSDC, 1);

        // weth fan token
        claimPool(fanTokenWETH, 0.001 ether);
        kickAuction(fanTokenWETH, poolToken, 10 ** poolToken.decimals());
        harvest(fanTokenWETH, 0.001 ether);
    }

    function claimPool(FanToken fanToken, uint256 minClaimAmount) public {
        // TODO: option to query an older pomotion id?
        uint256 promotionId = PRIZE_POOL_TWAB_REWARDS.latestPromotionId();
        console.log("promotionId:", promotionId);

        PrizePoolTwabRewards.Promotion memory promotion = PRIZE_POOL_TWAB_REWARDS.getPromotion(promotionId);

        address prizeVault = fanToken.asset();

        bytes32 claimMask = PRIZE_POOL_TWAB_REWARDS.claimedEpochs(promotionId, prizeVault, address(fanToken));

        uint8[] memory claimedEpochIds = PRIZE_POOL_TWAB_REWARDS.epochBytesToIdArray(claimMask);

        uint8 lastClaimedId = claimedEpochIds.length > 0 ? claimedEpochIds[claimedEpochIds.length - 1] : 0;

        uint8 nextClaimId = lastClaimedId + 1;

        if (nextClaimId >= promotion.numberOfEpochs) {
            console.log("No finished epochs to claim");
            return;
        }

        // Simulate the claim to check how much we would get
        uint256 claimableAmount =
            PRIZE_POOL_TWAB_REWARDS.claimRewardedEpochs(prizeVault, address(fanToken), promotionId, nextClaimId);

        console.log("claimable amount:", claimableAmount);

        if (claimableAmount < minClaimAmount) {
            console.log("Not enough rewards to claim");
            return;
        }

        vm.startBroadcast();

        PRIZE_POOL_TWAB_REWARDS.claimRewardedEpochs(prizeVault, address(fanToken), promotionId, nextClaimId);

        vm.stopBroadcast();
    }

    function harvest(FanToken fanToken, uint256 minHarvestAmount) public {
        uint256 harvestable = fanToken.harvestable();
        console.log("harvestable:", harvestable);

        if (harvestable < minHarvestAmount) {
            return;
        }

        vm.startBroadcast();

        fanToken.harvest();

        vm.stopBroadcast();
    }

    function kickAuction(FanToken fanToken, IERC20Metadata sellToken, uint256 minAuctionAmount) public {
        uint256 kickable = fanToken.kickable(address(sellToken));
        console.log("kickable", sellToken.symbol(), kickable);

        if (kickable < minAuctionAmount) {
            return;
        }

        vm.startBroadcast();

        fanToken.kickAuction(address(sellToken));

        vm.stopBroadcast();
    }
}
