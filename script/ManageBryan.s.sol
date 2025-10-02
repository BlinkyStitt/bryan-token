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

    IERC20Metadata public usdc;
    IERC20Metadata public weth;

    function setUp() public {
        // Read factory address from deployment artifacts for current chain
        // TODO: I'm not sure I like this. it should maybe read the addresses from a list saved somewhere instead?
        string memory chainId = vm.toString(block.chainid);
        string memory path = string(abi.encodePacked("./broadcast/DeployBryan.s.sol/", chainId, "/run-latest.json"));
        string memory json = vm.readFile(path);

        // Get the factory address to filter transactions
        string memory factoryPath =
            string(abi.encodePacked("./broadcast/DeployFanTokenFactory.s.sol/", chainId, "/run-latest.json"));
        string memory factoryJson = vm.readFile(factoryPath);
        address factory = vm.parseJsonAddress(factoryJson, ".transactions[0].contractAddress");

        // Parse transactions array length
        bytes memory lengthBytes = vm.parseJson(json, ".transactions");
        uint256 numTransactions = abi.decode(lengthBytes, (bytes[])).length;

        // Collect FanToken addresses by iterating through transactions
        address[] memory fanTokenAddrs = new address[](2);
        uint256 foundCount = 0;

        for (uint256 i = 0; i < numTransactions && foundCount < 2; i++) {
            string memory txPath = string(abi.encodePacked(".transactions[", vm.toString(i), "]"));

            // Check if this transaction is to the factory
            bytes memory contractAddrBytes = vm.parseJson(json, string(abi.encodePacked(txPath, ".contractAddress")));
            address contractAddr = abi.decode(contractAddrBytes, (address));

            if (contractAddr == factory) {
                // Get the first additional contract (the FanToken)
                bytes memory additionalContractsBytes =
                    vm.parseJson(json, string(abi.encodePacked(txPath, ".additionalContracts")));

                if (additionalContractsBytes.length > 0) {
                    bytes memory fanTokenAddrBytes =
                        vm.parseJson(json, string(abi.encodePacked(txPath, ".additionalContracts[0].address")));
                    fanTokenAddrs[foundCount] = abi.decode(fanTokenAddrBytes, (address));
                    foundCount++;
                }
            }
        }

        require(foundCount == 2, "Expected 2 FanToken deployments");

        // Identify which is USDC and which is WETH based on the asset
        for (uint256 i = 0; i < fanTokenAddrs.length; i++) {
            FanToken token = FanToken(payable(fanTokenAddrs[i]));
            IERC20Metadata underlying = IERC20Metadata(address(token.UNDERLYING()));

            string memory underlyingSymbol = underlying.symbol();

            if (LibString.eq(underlyingSymbol, "USDC")) {
                fanTokenUSDC = token;
                usdc = underlying;
            } else if (LibString.eq(underlyingSymbol, "WETH")) {
                fanTokenWETH = token;
                weth = underlying;
            }
        }

        require(address(usdc) != address(0), "no usdc found");
        require(address(weth) != address(0), "no weth found");

        // TODO: get this from PRIZE_POOL_TWAB_REWARDS?
        poolToken = IERC20Metadata(0xd652C5425aea2Afd5fb142e120FeCf79e18fafc3);
    }

    function run() public {
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

        console.log("num claimedEpochIds:", claimedEpochIds.length);

        uint8 lastClaimedId = claimedEpochIds.length > 0 ? claimedEpochIds[claimedEpochIds.length - 1] : 0;
        console.log("lastClaimedId:", lastClaimedId);

        uint8 nextClaimId = lastClaimedId + 1;
        console.log("nextClaimId:", nextClaimId);

        console.log("numberOfEpochs:", promotion.numberOfEpochs);

        // Get the current epoch ID from the contract
        uint8 currentEpochId = PRIZE_POOL_TWAB_REWARDS.getEpochIdNow(promotionId);
        console.log("currentEpochId:", currentEpochId);

        // Check if current epoch has ended
        (,uint48 currentEpochEndTimestamp,,) = PRIZE_POOL_TWAB_REWARDS.epochRangesForPromotion(promotionId, currentEpochId);
        bool currentEpochEnded = block.timestamp >= currentEpochEndTimestamp;
        
        // Determine the last claimable epoch
        uint8 lastEpochToCheck = currentEpochEnded ? currentEpochId : (currentEpochId > 0 ? currentEpochId - 1 : 0);
        console.log("lastEpochToCheck:", lastEpochToCheck);
        
        // Cap at numberOfEpochs
        if (lastEpochToCheck >= promotion.numberOfEpochs) {
            lastEpochToCheck = promotion.numberOfEpochs - 1;
        }

        if (nextClaimId > lastEpochToCheck || lastEpochToCheck == 0) {
            console.log("No finished epochs to claim");
            return;
        }

        // Build array of unclaimed epoch IDs
        uint256 numEpochsToCheck = lastEpochToCheck - nextClaimId + 1;
        uint8[] memory epochsToCheck = new uint8[](numEpochsToCheck);
        for (uint256 i = 0; i < numEpochsToCheck; i++) {
            epochsToCheck[i] = nextClaimId + uint8(i);
        }

        // Calculate rewards for each unclaimed epoch
        uint256[] memory rewards =
            PRIZE_POOL_TWAB_REWARDS.calculateRewards(prizeVault, address(fanToken), promotionId, epochsToCheck);

        // Filter to only epochs with non-zero rewards
        uint256 claimableCount = 0;
        for (uint256 i = 0; i < rewards.length; i++) {
            if (rewards[i] > 0) {
                claimableCount++;
            }
        }

        if (claimableCount == 0) {
            console.log("No epochs with claimable rewards");
            return;
        }

        uint8[] memory epochsToClaim = new uint8[](claimableCount);
        uint256 totalClaimable = 0;
        uint256 claimIndex = 0;
        for (uint256 i = 0; i < rewards.length; i++) {
            if (rewards[i] > 0) {
                epochsToClaim[claimIndex] = epochsToCheck[i];
                totalClaimable += rewards[i];
                claimIndex++;
                console.log("Epoch", uint256(epochsToCheck[i]), "claimable:", rewards[i]);
            }
        }

        console.log("Total claimable amount:", totalClaimable);

        if (totalClaimable < minClaimAmount) {
            console.log("Not enough rewards to claim");
            return;
        }

        vm.startBroadcast();

        PRIZE_POOL_TWAB_REWARDS.claimRewards(prizeVault, address(fanToken), promotionId, epochsToClaim);

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
