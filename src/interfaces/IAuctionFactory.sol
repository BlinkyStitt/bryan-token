// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.4;

interface IAuctionFactory {
    event DeployedNewAuction(address indexed auction, address indexed want);

    function DEFAULT_STARTING_PRICE() external view returns (uint256);
    function auctions(uint256) external view returns (address);
    function computeCreate2Address(address _original, bytes32 salt, address deployer)
        external
        view
        returns (address predicted);
    function computeCreate2Address(address _original, bytes32 salt) external view returns (address predicted);
    function computeCreate2Address(bytes32 salt) external view returns (address);
    function createNewAuction(address _want) external returns (address);
    function createNewAuction(address _want, address _receiver, address _governance, uint256 _startingPrice)
        external
        returns (address);
    function createNewAuction(address _want, address _receiver, address _governance) external returns (address);
    function createNewAuction(address _want, address _receiver) external returns (address);
    function createNewAuction(
        address _want,
        address _receiver,
        address _governance,
        uint256 _startingPrice,
        bytes32 _salt
    ) external returns (address);
    function getAllAuctions() external view returns (address[] memory);
    function getSalt(bytes32 salt, address deployer) external view returns (bytes32);
    function numberOfAuctions() external view returns (uint256);
    function original() external view returns (address);
    function version() external pure returns (string memory);
}
