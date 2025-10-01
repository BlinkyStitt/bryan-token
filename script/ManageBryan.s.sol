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
    PrizePoolTwabRewards constant PRIZE_POOL_TWAB_REWARDS = PrizePoolTwabRewards(0xF4c47dacFda99bE38793181af9Fd1A2Ec7576bBF);

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

        uint8 lastClaimedId = claimedEpochIds[claimedEpochIds.length - 1];

        // TODO: how can we calculate this?
        uint8[] memory unclaimedEpochIds;

        // TODO: make sure this is NOT broadcast!
        uint256[] memory unclaimedRewards = PRIZE_POOL_TWAB_REWARDS.calculateRewards(prizeVault, address(fanToken), promotionId, unclaimedEpochIds);

        uint256 numUnclaimedRewards = unclaimedRewards.length;

        uint256 sumUnclaimedRewards = 0;
        for (uint256 i = 0; i < numUnclaimedRewards; i++) {
            sumUnclaimedRewards += unclaimedRewards[i];
        }

        // TODO: min claim amounts
        if (sumUnclaimedRewards < minClaimAmount) {
            return;
        }

        // TODO: only claim if there are rewards to claim
        // TODO: query the blockchain to figure out if we even need to claim
        PRIZE_POOL_TWAB_REWARDS.claimRewardedEpochs(prizeVault, address(fanToken), promotionId, lastClaimedId + 1);
    }

    function harvest(FanToken fanToken, uint256 minHarvestAmount) public {
        // TODO: min harvest amounts
        if (fanToken.harvestable() == minHarvestAmount) {
            return;
        }

        vm.startBroadcast();

        fanToken.harvest();

        vm.stopBroadcast();
    }

    function kickAuction(FanToken fanToken, IERC20Metadata sellToken, uint256 minAuctionAmount) public {
        // TODO: min kick amounts
        if (fanToken.kickable(address(sellToken)) == minAuctionAmount) {
            return;
        }

        vm.startBroadcast();

        fanToken.kickAuction(address(sellToken));

        vm.stopBroadcast();
    }
}
