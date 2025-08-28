// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface PrizePool {
    type SD59x18 is int256;
    type UD60x18 is uint256;

    struct ConstructorParams {
        address prizeToken;
        address twabController;
        address creator;
        uint256 tierLiquidityUtilizationRate;
        uint48 drawPeriodSeconds;
        uint48 firstDrawOpensAt;
        uint24 grandPrizePeriodDraws;
        uint8 numberOfTiers;
        uint8 tierShares;
        uint8 canaryShares;
        uint8 reserveShares;
        uint24 drawTimeout;
    }

    struct Observation {
        uint96 available;
        uint160 disbursed;
    }

    struct ShutdownPortion {
        uint256 numerator;
        uint256 denominator;
    }

    error AddToDrawZero();
    error AlreadyClaimed(address vault, address winner, uint8 tier, uint32 prizeIndex);
    error AwardingDrawNotClosed(uint48 drawClosesAt);
    error CallerNotDrawManager(address caller, address drawManager);
    error ClaimPeriodExpired();
    error ContributionGTDeltaBalance(uint256 amount, uint256 available);
    error CreatorIsZeroAddress();
    error DidNotWin(address vault, address winner, uint8 tier, uint32 prizeIndex);

    // TODO: this conflicts with the event
    // error DrawAwarded(uint24 drawId, uint24 newestDrawId);

    error DrawManagerAlreadySet();
    error DrawTimeoutGTGrandPrizePeriodDraws();
    error DrawTimeoutIsZero();
    error FirstDrawOpensInPast();
    error GrandPrizePeriodDrawsTooLarge(uint24 grandPrizePeriodDraws, uint24 maxGrandPrizePeriodDraws);
    error IncompatibleTwabPeriodLength();
    error IncompatibleTwabPeriodOffset();
    error InsufficientLiquidity(uint104 requestedLiquidity);
    error InsufficientReserve(uint104 amount, uint104 reserve);
    error InsufficientRewardsError(uint256 requested, uint256 available);
    error InvalidDrawRange(uint24 startDrawId, uint24 endDrawId);
    error InvalidPrizeIndex(uint32 invalidPrizeIndex, uint32 prizeCount, uint8 tier);
    error InvalidTier(uint8 tier, uint8 numberOfTiers);
    error NoDrawsAwarded();
    error NumberOfTiersGreaterThanMaximum(uint8 numTiers);
    error NumberOfTiersLessThanMinimum(uint8 numTiers);
    error OnlyCreator();
    error PRBMath_MulDiv18_Overflow(uint256 x, uint256 y);
    error PRBMath_MulDiv_Overflow(uint256 x, uint256 y, uint256 denominator);
    error PRBMath_SD59x18_Ceil_Overflow(SD59x18 x);
    error PRBMath_SD59x18_Convert_Overflow(int256 x);
    error PRBMath_SD59x18_Convert_Underflow(int256 x);
    error PRBMath_SD59x18_Div_InputTooSmall();
    error PRBMath_SD59x18_Div_Overflow(SD59x18 x, SD59x18 y);
    error PRBMath_SD59x18_Exp2_InputTooBig(SD59x18 x);
    error PRBMath_SD59x18_Log_InputTooSmall(SD59x18 x);
    error PRBMath_SD59x18_Mul_InputTooSmall();
    error PRBMath_SD59x18_Mul_Overflow(SD59x18 x, SD59x18 y);
    error PRBMath_SD59x18_Sqrt_NegativeInput(SD59x18 x);
    error PRBMath_SD59x18_Sqrt_Overflow(SD59x18 x);
    error PRBMath_UD60x18_Convert_Overflow(uint256 x);
    error PrizeIsZero();
    error PrizePoolNotShutdown();
    error PrizePoolShutdown();
    error RandomNumberIsZero();
    error RangeSizeZero();
    error RewardRecipientZeroAddress();
    error RewardTooLarge(uint256 reward, uint256 maxReward);
    error TierLiquidityUtilizationRateCannotBeZero();
    error TierLiquidityUtilizationRateGreaterThanOne();
    error UpperBoundGtZero();

    event AllocateRewardFromReserve(address indexed to, uint256 amount);
    event ClaimedPrize(
        address indexed vault,
        address indexed winner,
        address indexed recipient,
        uint24 drawId,
        uint8 tier,
        uint32 prizeIndex,
        uint152 payout,
        uint96 claimReward,
        address claimRewardRecipient
    );
    event ContributePrizeTokens(address indexed vault, uint24 indexed drawId, uint256 amount);
    event ContributedReserve(address indexed user, uint256 amount);
    event DrawAwarded(
        uint24 indexed drawId,
        uint256 winningRandomNumber,
        uint8 lastNumTiers,
        uint8 numTiers,
        uint104 reserve,
        uint128 prizeTokensPerShare,
        uint48 drawOpenedAt
    );
    event IncreaseClaimRewards(address indexed to, uint256 amount);
    event ReserveConsumed(uint256 amount);
    event SetDrawManager(address indexed drawManager);
    event WithdrawRewards(address indexed account, address indexed to, uint256 amount, uint256 available);

    function DONATOR() external view returns (address);
    function accountedBalance() external view returns (uint256);
    function allocateRewardFromReserve(address _to, uint96 _amount) external;
    function awardDraw(uint256 winningRandomNumber_) external returns (uint24);
    function canaryShares() external view returns (uint8);
    function claimCount() external view returns (uint24);
    function claimPrize(
        address _winner,
        uint8 _tier,
        uint32 _prizeIndex,
        address _prizeRecipient,
        uint96 _claimReward,
        address _claimRewardRecipient
    ) external returns (uint256);
    function computeNextNumberOfTiers(uint32 _claimCount) external view returns (uint8);
    function computeRangeStartDrawIdInclusive(uint24 _endDrawIdInclusive, uint24 _rangeSize)
        external
        pure
        returns (uint24);
    function computeShutdownPortion(address _vault, address _account) external view returns (ShutdownPortion memory);
    function computeTotalShares(uint8 _numberOfTiers) external view returns (uint256);
    function contributePrizeTokens(address _prizeVault, uint256 _amount) external returns (uint256);
    function contributeReserve(uint96 _amount) external;
    function donatePrizeTokens(uint256 _amount) external;
    function drawClosesAt(uint24 drawId) external view returns (uint48);
    function drawManager() external view returns (address);
    function drawOpensAt(uint24 drawId) external view returns (uint48);
    function drawPeriodSeconds() external view returns (uint48);
    function drawTimeout() external view returns (uint24);
    function drawTimeoutAt() external view returns (uint256);
    function estimateNextNumberOfTiers() external view returns (uint8);
    function estimatedPrizeCount(uint8 numTiers) external view returns (uint32);
    function estimatedPrizeCount() external view returns (uint32);
    function estimatedPrizeCountWithBothCanaries(uint8 numTiers) external view returns (uint32);
    function estimatedPrizeCountWithBothCanaries() external view returns (uint32);
    function firstDrawOpensAt() external view returns (uint48);
    function getContributedBetween(address _vault, uint24 _startDrawIdInclusive, uint24 _endDrawIdInclusive)
        external
        view
        returns (uint256);
    function getDonatedBetween(uint24 _startDrawIdInclusive, uint24 _endDrawIdInclusive)
        external
        view
        returns (uint256);
    function getDrawId(uint256 _timestamp) external view returns (uint24);
    function getDrawIdToAward() external view returns (uint24);
    function getLastAwardedDrawId() external view returns (uint24);
    function getOpenDrawId() external view returns (uint24);
    function getShutdownDrawId() external view returns (uint24);
    function getShutdownInfo() external returns (uint256 balance, Observation memory observation);
    function getTierAccrualDurationInDraws(uint8 _tier) external view returns (uint24);
    function getTierOdds(uint8 _tier, uint8 _numTiers) external view returns (SD59x18);
    function getTierPrizeCount(uint8 _tier) external pure returns (uint32);
    function getTierPrizeSize(uint8 _tier) external view returns (uint104);
    function getTierRemainingLiquidity(uint8 _tier) external view returns (uint256);
    function getTotalAccumulatorNewestObservation() external view returns (Observation memory);
    function getTotalContributedBetween(uint24 _startDrawIdInclusive, uint24 _endDrawIdInclusive)
        external
        view
        returns (uint256);
    function getTotalShares() external view returns (uint256);
    function getVaultAccumulatorNewestObservation(address _vault) external view returns (Observation memory);
    function getVaultPortion(address _vault, uint24 _startDrawIdInclusive, uint24 _endDrawIdInclusive)
        external
        view
        returns (SD59x18);
    function getVaultUserBalanceAndTotalSupplyTwab(
        address _vault,
        address _user,
        uint24 _startDrawIdInclusive,
        uint24 _endDrawIdInclusive
    ) external view returns (uint256 twab, uint256 twabTotalSupply);
    function getWinningRandomNumber() external view returns (uint256);
    function grandPrizePeriodDraws() external view returns (uint24);
    function isCanaryTier(uint8 _tier) external view returns (bool);
    function isDrawFinalized(uint24 drawId) external view returns (bool);
    function isShutdown() external view returns (bool);
    function isWinner(address _vault, address _user, uint8 _tier, uint32 _prizeIndex) external view returns (bool);
    function lastAwardedDrawAwardedAt() external view returns (uint48);
    function numberOfTiers() external view returns (uint8);
    function pendingReserveContributions() external view returns (uint256);
    function prizeToken() external view returns (address);
    function prizeTokenPerShare() external view returns (uint128);
    function reserve() external view returns (uint96);
    function reserveShares() external view returns (uint8);
    function rewardBalance(address _recipient) external view returns (uint256);
    function setDrawManager(address _drawManager) external;
    function shutdownAt() external view returns (uint256);
    function shutdownBalanceOf(address _vault, address _account) external returns (uint256);
    function tierLiquidityUtilizationRate() external view returns (UD60x18);
    function tierShares() external view returns (uint8);
    function totalWithdrawn() external view returns (uint256);
    function twabController() external view returns (address);
    function wasClaimed(address _vault, address _winner, uint8 _tier, uint32 _prizeIndex)
        external
        view
        returns (bool);
    function wasClaimed(address _vault, address _winner, uint24 _drawId, uint8 _tier, uint32 _prizeIndex)
        external
        view
        returns (bool);
    function withdrawRewards(address _to, uint256 _amount) external;
    function withdrawShutdownBalance(address _vault, address _recipient) external returns (uint256);
}
