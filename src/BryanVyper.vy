#pragma version >0.4

# @dev example implementation of an ERC20 token
# @author Takayuki Jimba (@yudetamago)
# @author Bryan Stitt (@flashprofits.eth)
# https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20.md
# https://github.com/vyperlang/vyper/blob/master/examples/tokens/ERC20.vy

from ethereum.ercs import IERC20
from ethereum.ercs import IERC20Detailed

implements: IERC20
implements: IERC20Detailed

name: public(String[32])
symbol: public(String[32])

# TODO: how to make this immutable?
decimals: public(immutable(uint8))

billboard: public(String[1023])
billboardCost: public(uint256)

# NOTE: By declaring `balanceOf` as public, vyper automatically generates a 'balanceOf()' getter
#       method to allow access to account balances.
#       The _KeyType will become a required parameter for the getter and it will return _ValueType.
#       See: https://docs.vyperlang.org/en/v0.1.0-beta.8/types.html?highlight=getter#mappings
balanceOf: public(HashMap[address, uint256])

# By declaring `allowance` as public, vyper automatically generates the `allowance()` getter
allowance: public(HashMap[address, HashMap[address, uint256]])

# By declaring `totalSupply` as public, we automatically create the `totalSupply()` getter
totalSupply: public(uint256)

owner: address
nextOwner: address

event NextOwner:
    current: address
    next: address

event NewOwner:
    old: address
    new: address

event Billboard:
    author: indexed(address)
    message: String[1023]
    newCost: uint256


@deploy
def __init__(_name: String[32], _symbol: String[32], _decimals: uint8, _supply: uint256):
    init_supply: uint256 = _supply * 10 ** convert(_decimals, uint256)

    self.name = _name
    self.symbol = _symbol
    
    decimals = _decimals

    self._mint(msg.sender, init_supply)

    self.owner = msg.sender

#
# 2-phase transfer of ownership
#

@external
def setNextOwner(_next: address) -> bool:
    assert self.owner == msg.sender

    self.nextOwner = _next

    log NextOwner(current=msg.sender, next=_next)

    return True


@external
def claimOwnership():
    assert msg.sender == self.nextOwner

    # set to 1 instead of 0 to save gas
    self.nextOwner = convert(1, address)

    log NewOwner(old=self.owner, new=msg.sender)

    self.owner = msg.sender

#
# erc-20 things
#

@external
def transfer(_to : address, _value : uint256) -> bool:
    """
    @dev Transfer token for a specified address
    @param _to The address to transfer to.
    @param _value The amount to be transferred.
    """
    # NOTE: vyper does not allow underflows
    #       so the following subtraction would revert on insufficient balance
    self.balanceOf[msg.sender] -= _value
    self.balanceOf[_to] += _value
    log IERC20.Transfer(sender=msg.sender, receiver=_to, value=_value)
    return True


@external
def transferFrom(_from : address, _to : address, _value : uint256) -> bool:
    """
     @dev Transfer tokens from one address to another.
     @param _from address The address which you want to send tokens from
     @param _to address The address which you want to transfer to
     @param _value uint256 the amount of tokens to be transferred
    """
    # NOTE: vyper does not allow underflows
    #       so the following subtraction would revert on insufficient balance
    self.balanceOf[_from] -= _value
    self.balanceOf[_to] += _value
    # NOTE: vyper does not allow underflows
    #      so the following subtraction would revert on insufficient allowance
    # TODO: if allowance is max, don't actually subtract to save some gas
    self.allowance[_from][msg.sender] -= _value
    log IERC20.Transfer(sender=_from, receiver=_to, value=_value)
    return True


@external
def approve(_spender : address, _value : uint256) -> bool:
    """
    @dev Approve the passed address to spend the specified amount of tokens on behalf of msg.sender.
         Beware that changing an allowance with this method brings the risk that someone may use both the old
         and the new allowance by unfortunate transaction ordering. One possible solution to mitigate this
         race condition is to first reduce the spender's allowance to 0 and set the desired value afterwards:
         https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
    @param _spender The address which will spend the funds.
    @param _value The amount of tokens to be spent.
    """
    self.allowance[msg.sender][_spender] = _value
    log IERC20.Approval(owner=msg.sender, spender=_spender, value=_value)
    return True


@internal
def _mint(_to: address, _value: uint256):
    """
    @dev Mint an amount of the token and assigns it to an account.
         This encapsulates the modification of balances such that the
         proper events are emitted.
    @param _to The account that will receive the created tokens.
    @param _value The amount that will be created.
    """
    assert _to != empty(address)
    self.totalSupply += _value
    self.balanceOf[_to] += _value
    log IERC20.Transfer(sender=empty(address), receiver=_to, value=_value)


@external
def mint(_to: address, _value: uint256):
    """
    @dev Mint an amount of the token and assigns it to an account.
         This encapsulates the modification of balances such that the
         proper events are emitted.
    @dev only the owner can call this function. This is not an investment, this is an experiment.
    @param _to The account that will receive the created tokens.
    @param _value The amount that will be created.
    """
    assert msg.sender == self.owner
    self._mint(_to, _value)


@internal
def _burn(_to: address, _value: uint256):
    """
    @dev Internal function that burns an amount of the token of a given
         account.
    @param _to The account whose tokens will be burned.
    @param _value The amount that will be burned.
    """
    assert _to != empty(address)
    self.totalSupply -= _value
    self.balanceOf[_to] -= _value
    log IERC20.Transfer(sender=_to, receiver=empty(address), value=_value)


@external
def burn(_value: uint256):
    """
    @dev Burn an amount of the token of msg.sender.
    @param _value The amount that will be burned.
    """
    self._burn(msg.sender, _value)


@external
def burnFrom(_to: address, _value: uint256):
    """
    @dev Burn an amount of the token from a given account.
    @dev The owner can burn from any account.
    @param _to The account whose tokens will be burned.
    @param _value The amount that will be burned.
    """
    if msg.sender != self.owner: 
        self.allowance[_to][msg.sender] -= _value
    self._burn(_to, _value)

#
# billboard
# 

@external
def yoink(message: String[1023]):
    """
    @dev claim the billboard if you have enough of the token.
    """
    senderBalance: uint256 = self.balanceOf[msg.sender]

    assert senderBalance > self.billboardCost

    self.billboardCost = senderBalance
    self.billboard = message

    log Billboard(author=msg.sender, message=message, newCost=senderBalance)
