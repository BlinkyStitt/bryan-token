// SPDX-License-Identifier: AGPL-3.0-only
// libraries are good, but I'm just wanting to experiment. This is not decentralized.
pragma solidity 0.8.30;

contract Bryan {
    string public name;
    string public symbol;
    uint8 public immutable decimals = 18;

    /// @notice owner-settable description
    string public description;

    /// @notice owner-settable uri
    string public website;

    /// @notice fan-settable things. get the most BRY and you can set this!
    string public billboard;

    /// @notice the balance of the last user to set 
    uint256 public billboardCost;

    address public owner;
    address public nextOwner;

    /// @dev Do not manually set balances without updating totalSupply, as the sum of all user balances must not exceed it.
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);

    event Billboard(address indexed _from, string _msg, uint256 _newCost);

    constructor() {
        name = "Bryan";
        symbol = "BRY";
        description = "Just for fun.";
        website = "https://farcaster.xyz/flashprofits.eth";

        owner = msg.sender;

        _mint(msg.sender, 10_000);
    }

    // 
    // modifiers
    //

    modifier ownerOnly() {
        require(msg.sender == owner);
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
        // TODO: event?
        return true;
    }

    function setSymbol(string calldata newSymbol) ownerOnly public returns (bool success) {
        symbol = newSymbol;
        // TODO: event?
        return true;
    }

    function setDescription(string calldata newDescription) ownerOnly public returns (bool success) {
        description = newDescription;
        // TODO: event?
        return true;
    }

    function setWebsite(string calldata newWebsite) ownerOnly public returns (bool success) {
        website = newWebsite;
        // TODO: event?
        return true;
    }

    function setBillboard(string calldata newBillboard) ownerOnly public returns (bool success) {
        billboard = newBillboard;

        emit Billboard(msg.sender, newBillboard, billboardCost);

        return true;
    }

    function setBillboardCost(uint256 newCost) ownerOnly public returns (bool success) {
        billboardCost = newCost;
        // TODO: event?
        return true;
    }

    function setNextOwner(address newOwner) ownerOnly public returns (bool success) {
        nextOwner = newOwner;
        // TODO: event?
        return true;
    }

    function claimOwnership() public returns (bool success) {
        require(msg.sender == nextOwner);
        owner = nextOwner;
        nextOwner = address(1);
        // TODO: event?
        return true;
    }

    //
    // internal
    //

    function _mint(address to, uint256 amount) internal virtual {
        totalSupply += amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal virtual {
        balanceOf[from] -= amount;

        // Cannot underflow because a user's balance
        // will never be larger than the total supply.
        unchecked {
            totalSupply -= amount;
        }

        emit Transfer(from, address(0), amount);
    }

    // billboard things

    function claimBillboard(string calldata newBillboard) public returns (bool) {
        uint256 senderBalance = balanceOf[msg.sender];

        require(senderBalance > billboardCost);

        billboardCost = senderBalance;
        billboard = newBillboard;

        emit Billboard(msg.sender, newBillboard, senderBalance);

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
}
