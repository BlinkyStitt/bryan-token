// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface IAuction {
    event AuctionDisabled(address indexed from, address indexed to);
    event AuctionEnabled(address indexed from, address indexed to);
    event AuctionKicked(address indexed from, uint256 available);
    event AuctionSettled(address indexed from);
    event AuctionSwept(address indexed token, address indexed to);
    event GovernanceTransferred(address indexed previousGovernance, address indexed newGovernance);
    event UpdatePendingGovernance(address indexed newPendingGovernance);
    event UpdatedStartingPrice(uint256 startingPrice);
    event UpdatedStepDecayRate(uint256 indexed stepDecayRate);
    event UpdatedStepDuration(uint256 indexed stepDuration);

    function acceptGovernance() external;
    function auctionLength() external view returns (uint256);
    function auctions(address) external view returns (uint64 kicked, uint64 scaler, uint128 initialAvailable);
    function available(address _from) external view returns (uint256);
    function disable(address _from) external;
    function disable(address _from, uint256 _index) external;
    function enable(address _from) external;
    function enabledAuctions(uint256) external view returns (address);
    function forceKick(address _from) external;
    function getAllEnabledAuctions() external view returns (address[] memory);
    function getAmountNeeded(address _from) external view returns (uint256);
    function getAmountNeeded(address _from, uint256 _amountToTake, uint256 _timestamp)
        external
        view
        returns (uint256);
    function getAmountNeeded(address _from, uint256 _amountToTake) external view returns (uint256);
    function governance() external view returns (address);
    function initialize(address _want, address _receiver, address _governance, uint256 _startingPrice) external;
    function isActive(address _from) external view returns (bool);
    function isAnActiveAuction() external view returns (bool);
    function isValidSignature(bytes32 _hash, bytes memory signature) external view returns (bytes4);
    function kick(address _from) external returns (uint256 _available);
    function kickable(address _from) external view returns (uint256);
    function kicked(address _from) external view returns (uint256);
    function pendingGovernance() external view returns (address);
    function price(address _from, uint256 _timestamp) external view returns (uint256);
    function price(address _from) external view returns (uint256);
    function receiver() external view returns (address);
    function setStartingPrice(uint256 _startingPrice) external;
    function setStepDecayRate(uint256 _stepDecayRate) external;
    function setStepDuration(uint256 _stepDuration) external;
    function settle(address _from) external;
    function startingPrice() external view returns (uint256);
    function stepDecayRate() external view returns (uint256);
    function stepDuration() external view returns (uint256);
    function sweep(address _token) external;
    function take(address _from) external returns (uint256);
    function take(address _from, uint256 _maxAmount) external returns (uint256);
    function take(address _from, uint256 _maxAmount, address _takerReceiver, bytes memory _data)
        external
        returns (uint256);
    function take(address _from, uint256 _maxAmount, address _takerReceiver) external returns (uint256);
    function transferGovernance(address _newGovernance) external;
    function version() external pure returns (string memory);
    function want() external view returns (address);
}
