// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface PrizePoolTwabRewards {
    struct Promotion {
        address token;
        uint40 epochDuration;
        uint40 createdAt;
        uint8 numberOfEpochs;
        uint40 startTimestamp;
        uint104 tokensPerEpoch;
        uint112 rewardsUnclaimed;
    }

    error EpochDurationLtDrawPeriod();
    error EpochDurationNotMultipleOfDrawPeriod();
    error EpochNotOver(uint64 epochEndTimestamp);
    error ExceedsMaxEpochs(uint8 epochExtension, uint8 currentEpochs, uint8 maxEpochs);
    error GracePeriodActive(uint256 gracePeriodEndTimestamp);
    error InvalidEpochId(uint8 epochId, uint8 numberOfEpochs);
    error NoEpochsToClaim(uint8 startEpochId, uint8 currentEpochId);
    error OnlyPromotionCreator(address sender, address creator);
    error PayeeZeroAddress();
    error PrizePoolZeroAddress();
    error PromotionInactive(uint256 promotionId);
    error StartTimeLtFirstDrawOpensAt();
    error StartTimeNotAlignedWithDraws();
    error TokensReceivedLessThanExpected(uint256 received, uint256 expected);
    error TwabControllerZeroAddress();
    error ZeroEpochs();
    error ZeroTokensPerEpoch();

    event PromotionCreated(
        uint256 indexed promotionId,
        address indexed token,
        uint40 startTimestamp,
        uint104 tokensPerEpoch,
        uint40 epochDuration,
        uint8 initialNumberOfEpochs
    );
    event PromotionDestroyed(uint256 indexed promotionId, address indexed recipient, uint256 amount);
    event PromotionEnded(uint256 indexed promotionId, address indexed recipient, uint256 amount, uint8 epochNumber);
    event PromotionExtended(uint256 indexed promotionId, uint256 numberOfEpochs);
    event RewardsClaimed(
        uint256 indexed promotionId,
        bytes32 epochClaimFlags,
        address indexed vault,
        address indexed user,
        uint256 amount
    );

    function GRACE_PERIOD() external view returns (uint32);
    function SPONSORSHIP_ADDRESS() external view returns (address);
    function calculateDrawIdAt(uint64 _timestamp) external view returns (uint24);
    function calculateRewards(address _vault, address _user, uint256 _promotionId, uint8[] memory _epochIds)
        external
        returns (uint256[] memory rewards);
    function claimRewardedEpochs(address _vault, address _user, uint256 _promotionId, uint8 _startEpochId)
        external
        returns (uint256);
    function claimRewards(address _vault, address _user, uint256 _promotionId, uint8[] memory _epochIds)
        external
        returns (uint256);
    function claimTwabRewards(address _twabRewards, address _user, uint256 _promotionId, uint8[] memory _epochIds)
        external
        returns (uint256);
    function claimedEpochs(uint256 promotionId, address vault, address user)
        external
        view
        returns (bytes32 claimMask);
    function createPromotion(
        address _token,
        uint40 _startTimestamp,
        uint104 _tokensPerEpoch,
        uint40 _epochDuration,
        uint8 _numberOfEpochs
    ) external returns (uint256);
    function destroyPromotion(uint256 _promotionId, address _to) external returns (bool);
    function endPromotion(uint256 _promotionId, address _to) external returns (bool);
    function epochBytesToIdArray(bytes32 _epochClaimFlags) external pure returns (uint8[] memory);
    function epochIdArrayToBytes(uint8[] memory _epochIds) external pure returns (bytes32);
    function epochRanges(uint48 _promotionStartTimestamp, uint48 _promotionEpochDuration, uint8 _epochId)
        external
        view
        returns (uint48 epochStartTimestamp, uint48 epochEndTimestamp, uint24 epochStartDrawId, uint24 epochEndDrawId);
    function epochRangesForPromotion(uint256 _promotionId, uint8 _epochId)
        external
        view
        returns (uint48 epochStartTimestamp, uint48 epochEndTimestamp, uint24 epochStartDrawId, uint24 epochEndDrawId);
    function extendPromotion(uint256 _promotionId, uint8 _numberOfEpochs) external returns (bool);
    function getEpochIdAt(uint256 _promotionId, uint256 _timestamp) external view returns (uint8);
    function getEpochIdNow(uint256 _promotionId) external view returns (uint8);
    function getPromotion(uint256 _promotionId) external view returns (Promotion memory);
    function getRemainingRewards(uint256 _promotionId) external view returns (uint128);
    function getVaultRewardAmount(address _vault, uint256 _promotionId, uint8 _epochId) external returns (uint128);
    function latestPromotionId() external view returns (uint256);
    function multicall(bytes[] memory data) external returns (bytes[] memory results);
    function prizePool() external view returns (address);
    function promotionCreators(uint256) external view returns (address);
    function twabController() external view returns (address);
}
