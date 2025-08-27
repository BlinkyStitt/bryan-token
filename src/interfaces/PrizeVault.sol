// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface PrizeVault {
    struct PrizeHooks {
        bool useBeforeClaimPrize;
        bool useAfterClaimPrize;
        address implementation;
    }

    error BurnZeroShares();
    error CallerNotClaimer(address caller, address claimer);
    error CallerNotLP(address caller, address liquidationPair);
    error CallerNotYieldFeeRecipient(address caller, address yieldFeeRecipient);
    error ClaimRecipientZeroAddress();
    error ClaimerZeroAddress();
    error DepositZeroAssets();
    error FailedToGetAssetDecimals(address asset);
    error InvalidShortString();
    error LPZeroAddress();
    error LiquidationAmountOutZero();
    error LiquidationExceedsAvailable(uint256 totalToWithdraw, uint256 availableYield);
    error LiquidationTokenInNotPrizeToken(address tokenIn, address prizeToken);
    error LiquidationTokenOutNotSupported(address tokenOut);
    error LossyDeposit(uint256 totalAssets, uint256 totalSupply);
    error MaxSharesExceeded(uint256 shares, uint256 maxShares);
    error MinAssetsNotReached(uint256 assets, uint256 minAssets);
    error MintLimitExceeded(uint256 excess);
    error MintZeroShares();
    error OwnerZeroAddress();
    error PermitCallerNotOwner(address caller, address owner);
    error PrizePoolZeroAddress();
    error SharesExceedsYieldFeeBalance(uint256 shares, uint256 yieldFeeBalance);
    error StringTooLong(string str);
    error TwabControllerZeroAddress();
    error WithdrawZeroAssets();
    error YieldFeePercentageExceedsMax(uint256 yieldFeePercentage, uint256 maxYieldFeePercentage);
    error YieldVaultZeroAddress();
    error ZeroTotalAssets();

    event Approval(address indexed owner, address indexed spender, uint256 value);
    event ClaimYieldFeeShares(address indexed recipient, uint256 shares);
    event ClaimerSet(address indexed claimer);
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event EIP712DomainChanged();
    event LiquidationPairSet(address indexed tokenOut, address indexed liquidationPair);
    event OwnershipOffered(address indexed pendingOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event SetHooks(address indexed account, PrizeHooks hooks);
    event Sponsor(address indexed caller, uint256 assets, uint256 shares);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event TransferYieldOut(
        address indexed liquidationPair,
        address indexed tokenOut,
        address indexed recipient,
        uint256 amountOut,
        uint256 yieldFee
    );
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );
    event YieldFeePercentageSet(uint256 yieldFeePercentage);
    event YieldFeeRecipientSet(address indexed yieldFeeRecipient);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function FEE_PRECISION() external view returns (uint32);
    function HOOK_GAS() external view returns (uint24);
    function MAX_YIELD_FEE() external view returns (uint32);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function asset() external view returns (address);
    function availableYieldBalance() external view returns (uint256);
    function balanceOf(address _account) external view returns (uint256);
    function claimOwnership() external;
    function claimPrize(address _winner, uint8 _tier, uint32 _prizeIndex, uint96 _reward, address _rewardRecipient)
        external
        returns (uint256);
    function claimYieldFeeShares(uint256 _shares) external;
    function claimer() external view returns (address);
    function convertToAssets(uint256 _shares) external view returns (uint256);
    function convertToShares(uint256 _assets) external view returns (uint256);
    function currentYieldBuffer() external view returns (uint256);
    function decimals() external view returns (uint8);
    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool);
    function deposit(uint256 _assets, address _receiver) external returns (uint256);
    function depositWithPermit(uint256 _assets, address _owner, uint256 _deadline, uint8 _v, bytes32 _r, bytes32 _s)
        external
        returns (uint256);
    function eip712Domain()
        external
        view
        returns (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        );
    function getHooks(address account) external view returns (PrizeHooks memory);
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool);
    function isLiquidationPair(address _tokenOut, address _liquidationPair) external view returns (bool);
    function liquidatableBalanceOf(address _tokenOut) external view returns (uint256);
    function liquidationPair() external view returns (address);
    function maxDeposit(address) external view returns (uint256);
    function maxMint(address _owner) external view returns (uint256);
    function maxRedeem(address _owner) external view returns (uint256);
    function maxWithdraw(address _owner) external view returns (uint256);
    function mint(uint256 _shares, address _receiver) external returns (uint256);
    function name() external view returns (string memory);
    function nonces(address owner) external view returns (uint256);
    function owner() external view returns (address);
    function pendingOwner() external view returns (address);
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;
    function previewDeposit(uint256 _assets) external pure returns (uint256);
    function previewMint(uint256 _shares) external pure returns (uint256);
    function previewRedeem(uint256 _shares) external view returns (uint256);
    function previewWithdraw(uint256 _assets) external view returns (uint256);
    function prizePool() external view returns (address);
    function redeem(uint256 _shares, address _receiver, address _owner, uint256 _minAssets)
        external
        returns (uint256);
    function redeem(uint256 _shares, address _receiver, address _owner) external returns (uint256);
    function renounceOwnership() external;
    function setClaimer(address _claimer) external;
    function setHooks(PrizeHooks memory hooks) external;
    function setLiquidationPair(address _liquidationPair) external;
    function setYieldFeePercentage(uint32 _yieldFeePercentage) external;
    function setYieldFeeRecipient(address _yieldFeeRecipient) external;
    function sponsor(uint256 _assets) external returns (uint256);
    function symbol() external view returns (string memory);
    function targetOf(address) external view returns (address);
    function totalAssets() external view returns (uint256);
    function totalDebt() external view returns (uint256);
    function totalPreciseAssets() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function totalYieldBalance() external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transferOwnership(address _newOwner) external;
    function transferTokensOut(address, address _receiver, address _tokenOut, uint256 _amountOut)
        external
        returns (bytes memory);
    function twabController() external view returns (address);
    function verifyTokensIn(address _tokenIn, uint256 _amountIn, bytes memory) external;
    function withdraw(uint256 _assets, address _receiver, address _owner, uint256 _maxShares)
        external
        returns (uint256);
    function withdraw(uint256 _assets, address _receiver, address _owner) external returns (uint256);
    function yieldBuffer() external view returns (uint256);
    function yieldFeeBalance() external view returns (uint256);
    function yieldFeePercentage() external view returns (uint32);
    function yieldFeeRecipient() external view returns (address);
    function yieldVault() external view returns (address);
}
