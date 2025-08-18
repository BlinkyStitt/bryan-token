// SPDX-License-Identifier: AGPL-3.0-only
// This is an experiment in a "social token". It is an ERC-20 with some extra pieces.
// TODO: permit for allowances? the name can change and that complicates things. <https://docs.openzeppelin.com/contracts/5.x/api/token/erc20#ERC20Permit>
pragma solidity ^0.8.13;

import {Base64} from "@solady/utils/Base64.sol";
import {LibString} from "@solady/utils/LibString.sol";

error Unauthorized();
error LowBalance();

contract Bryan {
    using LibString for uint256;

    string public name;
    string public symbol;
    uint8 public immutable decimals;

    /// @notice owner-settable description
    string public description;

    /// @notice owner-settable image
    string public image;

    /// @notice owner-settable uri
    string public website;

    /// @notice fan-settable things. get the most BRY and you can set this!
    string public billboard;

    /// @notice the balance of the last user to set the billboard
    uint256 public billboardCost;

    /// @notice the address of the last user to set the billboard
    address public billboardAuthor;

    /// @notice the current owner of the contract. has power to mint and burn
    /// @dev With a smart-contract as the owner, more advancted authentication can be added.
    address public owner;

    /// @notice the next owner of the contract. will have the power to mint and burn after claiming ownership
    address public nextOwner;

    /// @notice the total supply of this erc20 token
    /// @dev Do not manually set balances without updating totalSupply, as the sum of all user balances must not exceed it.
    uint256 public totalSupply;

    /// @notice the balances of this erc20 token
    mapping(address => uint256) public balanceOf;

    /// @notice the allowances of this erc20 token
    mapping(address => mapping(address => uint256)) public allowance;

    event Approval(address indexed _owner, address indexed _spender, uint256 _value);
    event Transfer(address indexed _from, address indexed _to, uint256 _value);

    event NextOwner(address indexed _from, address indexed _to);
    event ClaimOwnership(address indexed _from, address indexed _to);

    event NewBillboard(address indexed _from, string _msg, uint256 _newCost);
    event NewDescription(string _description);
    event NewImage(string _image);
    event NewName(string _name);
    event NewSymbol(string _symbol);
    event NewWebsite(string _website);

    /// todo: what order should these arguments be in? does it matter?
    constructor(
        string memory _name,
        string memory _symbol,
        string memory _description,
        string memory _image,
        string memory _website,
        address _owner,
        uint8 _decimals,
        uint256 _supply
    ) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;

        description = _description;
        image = _image;
        website = _website;

        emit ClaimOwnership(address(0), _owner);
        emit NewName(_name);
        emit NewSymbol(_symbol);
        emit NewDescription(_description);
        emit NewImage(_image);
        emit NewWebsite(_website);

        owner = _owner;

        _mint(_owner, _supply);
    }

    //
    // modifiers
    //
    modifier ownerOnly() {
        require(msg.sender == owner, Unauthorized());
        _;
    }

    //
    // owner-only
    //
    function ownerBurn(address from, uint256 amount) public ownerOnly returns (bool success) {
        _burn(from, amount);
        return true;
    }

    function ownerMint(address to, uint256 amount) public ownerOnly returns (bool success) {
        _mint(to, amount);
        return true;
    }

    function setName(string calldata newName) public ownerOnly returns (bool success) {
        name = newName;
        emit NewName(newName);
        return true;
    }

    function setSymbol(string calldata newSymbol) public ownerOnly returns (bool success) {
        symbol = newSymbol;
        emit NewSymbol(newSymbol);
        return true;
    }

    function setDescription(string calldata newDescription) public ownerOnly returns (bool success) {
        description = newDescription;
        emit NewDescription(newDescription);
        return true;
    }

    function setImage(string calldata newImage) public ownerOnly returns (bool success) {
        image = newImage;
        emit NewImage(newImage);
        return true;
    }

    function setWebsite(string calldata newWebsite) public ownerOnly returns (bool success) {
        website = newWebsite;
        emit NewWebsite(newWebsite);
        return true;
    }

    function ownerBillboard(string calldata newBillboard, uint256 newCost) public ownerOnly returns (bool success) {
        _billboard(msg.sender, newBillboard, newCost);
        return true;
    }

    function ownerBillboardCost(uint256 newCost) public ownerOnly returns (bool success) {
        billboardCost = newCost;
        emit NewBillboard(billboardAuthor, billboard, newCost);
        return true;
    }

    function setNextOwner(address newOwner) public ownerOnly returns (bool success) {
        nextOwner = newOwner;
        emit NextOwner(msg.sender, newOwner);
        return true;
    }

    function claimOwnership() public returns (bool success) {
        require(msg.sender == nextOwner);

        emit ClaimOwnership(owner, nextOwner);

        owner = nextOwner;
        nextOwner = address(1);

        return true;
    }

    //
    // internal
    //
    function _billboard(address author, string calldata newBillboard, uint256 newCost) internal {
        billboardAuthor = author;
        billboard = newBillboard;
        billboardCost = newCost;
        emit NewBillboard(author, newBillboard, newCost);
    }

    function _mint(address to, uint256 amount) internal {
        totalSupply += amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal {
        balanceOf[from] -= amount;

        // Cannot underflow because a user's balance
        // will never be larger than the total supply.
        unchecked {
            totalSupply -= amount;
        }

        emit Transfer(from, address(0), amount);
    }

    //
    // fun and games
    //

    /// @notice yoink the billboard with any message you want.
    /// @dev the billboard can be claimed by the person with the most BRY.
    /// @dev the owner contract can take the billboard back at any time.
    function yoink(string calldata newBillboard) public returns (bool) {
        uint256 senderBalance = balanceOf[msg.sender];
        require(senderBalance > billboardCost, LowBalance());

        // we don't update billboardCost to avoid flash loans causing trickery
        uint256 authorBalance = balanceOf[billboardAuthor];
        require(senderBalance > authorBalance, LowBalance());

        _billboard(msg.sender, newBillboard, senderBalance);

        return true;
    }

    //
    // standard erc20 things
    //
    function approve(address spender, uint256 amount) public returns (bool) {
        allowance[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);

        return true;
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        balanceOf[msg.sender] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(msg.sender, to, amount);

        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.

        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;

        balanceOf[from] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);

        return true;
    }

    //
    // non-standard token things
    //
    function burn(uint256 amount) public returns (bool success) {
        _burn(msg.sender, amount);
        return true;
    }

    function burnFrom(address from, uint256 amount) public returns (bool success) {
        uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.

        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;

        _burn(from, amount);
        return true;
    }

    /// @dev the billboard is base64 encoded because it should be filtered before being displayed.
    function tokenURI() public view returns (string memory) {
        bytes memory json = abi.encodePacked(
            '{"name":"',
            name,
            '",',
            '"symbol":"',
            symbol,
            '",',
            '"decimals":',
            uint256(decimals).toString(),
            ",",
            '"description":"',
            description,
            '",',
            '"image":"',
            image,
            '",',
            '"billboard":"',
            Base64.encode(bytes(billboard)),
            '",',
            '"website":"',
            website,
            '"}'
        );
        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(json)));
    }
}
