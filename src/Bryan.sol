// SPDX-License-Identifier: AGPL-3.0-only
// libraries are good, but I'm just wanting to experiment. This is not decentralized.
pragma solidity 0.8.30;

import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";

error Unauthorized();

contract BryanSol {
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
    address public owner;

    /// @notice the next owner of the contract. will have the power to mint and burn after claiming ownership
    address public nextOwner;

    /// @dev Do not manually set balances without updating totalSupply, as the sum of all user balances must not exceed it.
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);

    event NextOwner(address indexed _from, address indexed _to);
    event ClaimOwnership(address indexed _from, address indexed _to);

    event NewName(string _name);
    event NewSymbol(string _symbol);
    event NewDescription(string _description);
    event NewImage(string _image);
    event NewWebsite(string _website);

    event NewBillboard(address indexed _from, string _msg, uint256 _newCost);

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _description,
        string memory _image,
        string memory _website,
        uint8 _decimals,
        uint256 _supply
    ) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;

        description = _description;
        image = _image;
        website = _website;

        emit ClaimOwnership(address(0), msg.sender);
        emit NewName(_name);
        emit NewSymbol(_symbol);
        emit NewDescription(_description);
        emit NewImage(_image);
        emit NewWebsite(_website);

        owner = msg.sender;

        _mint(msg.sender, _supply);
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

    function burn(address from, uint256 amount) ownerOnly public returns (bool success) {
        _burn(from, amount);
        return true;
    }

    function mint(address to, uint256 amount) ownerOnly public returns (bool success) {
        _mint(to, amount);
        return true;
    }

    function setName(string calldata newName) ownerOnly public returns (bool success) {
        name = newName;
        emit NewName(newName);
        return true;
    }

    function setSymbol(string calldata newSymbol) ownerOnly public returns (bool success) {
        symbol = newSymbol;
        emit NewSymbol(newSymbol);
        return true;
    }

    function setDescription(string calldata newDescription) ownerOnly public returns (bool success) {
        description = newDescription;
        emit NewDescription(newDescription);
        return true;
    }

    function setImage(string calldata newImage) ownerOnly public returns (bool success) {
        image = newImage;
        emit NewImage(newImage);
        return true;
    }

    function setWebsite(string calldata newWebsite) ownerOnly public returns (bool success) {
        website = newWebsite;
        emit NewWebsite(newWebsite);
        return true;
    }

    function setBillboard(string calldata newBillboard, uint256 newCost) ownerOnly public returns (bool success) {
        _billboard(msg.sender, newBillboard, newCost);
        return true;
    }

    function setBillboardCost(uint256 newCost) ownerOnly public returns (bool success) {
        billboardCost = newCost;
        emit NewBillboard(billboardAuthor, billboard, newCost);
        return true;
    }

    function setNextOwner(address newOwner) ownerOnly public returns (bool success) {
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

    // billboard things

    function yoink(string calldata newBillboard) public returns (bool) {
        uint256 senderBalance = balanceOf[msg.sender];
        require (senderBalance > billboardCost);

        // we don't update billboardCost to avoid flash loans causing trickery
        require (senderBalance > balanceOf[billboardAuthor]);

        _billboard(msg.sender, newBillboard, senderBalance);

        return true;
    }

    //
    // erc20 things
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

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public returns (bool) {
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

    // TODO: put billboard here? if people aren't careful they could break the json so I don't think so.
    function tokenURI() public view returns (string memory) {
        bytes memory json = abi.encodePacked(
            '{"name":"', name, '",',
            '"symbol":"', symbol, '",',
            '"decimals":"', decimals, '",',
            '"description":"', description, '",',
            '"image":"', image, '",',
            '"website":"', website, '"}'
        );
        return string(
            abi.encodePacked("data:application/json;base64,", Base64.encode(json))
        );
    }
}
