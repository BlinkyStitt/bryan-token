# Fan Tokens

**This project is ABANDONED**. I learned what I needed from this experiment. The more I talked with people about creator/fan tokens, the less excited I became. I don't think its worth my time to solve the remaining edge cases and write a mini-app.

A **tipping and gaming token** for social interactions, particularly on platforms like Farcaster. Think of fan tokens as "wrapping paper" around valuable assets - they make tips more personal and engaging than generic USDC or ETH transfers.

## What Are Fan Tokens?

**🎁 Personalized Tipping Tokens**
- Custom wrapping tokens that represent support for a creator or community member
- Meant to be given as gifts, not bought/sold on markets
- Each token is backed by PoolTogether vault deposits

**🏆 Shared Prizes**
- Token holders participate in daily [PoolTogether prize](https://pooltogether.com/) drawings
- Any prize winnings or other rewards are distributed among the owner, the treasury, and the token holders
- Token creators set custom harvest fee percentages for owner and treasury. These fees cannot be changed once the token is created.
- Users can enable sponsorship if they do not want to earn any prizes. The owner is a sponsor by default.

**💰 Always Redeemable**
- Tokens can always be redeemed for the underlying PoolTogether vault tokens
- Vault tokens are backed by valuable assets like ETH or USDC
- Minimized risk of tokens becoming worthless due to backing mechanism

## Warning!

- This is an experiment and a toy.
- This is not audited.

## How It Works

**🏗️ Technical Architecture**
- Built as ERC4626 vaults on top of Pool Together vaults
- Deployed to the Base network, but will work on any network that has pool together.
- Using Solidity with the Foundry framework
- FanTokenFactory deploys FanToken contracts
- Integration with Yearn's dutch auctions for yield harvesting
- Uniswap V4 hook integration via Generic4626Router so that wallets can easily show pricing

**🛡️ "Can't Be Evil" Design Principles**
- Contracts are immutable once deployed
- Token settings (name, symbol, fees) cannot be changed after creation
- Backing mechanism prevents "pump and dump" scenarios
- All functions designed to be maximally fair to participants
- No "owner-only" functions. Every function is designed to be open for anyone to call.

**⏰ Safety Mechanisms**
- 3-day deposit delays prevent unfair prize extraction after large wins
- Dutch auction system ensures fair price discovery for yield distribution

## Problems Left To Check and Fix

TODO: If the vault suffers losses, we need to make sure the sponsors can't take an unfair share. It might be fine, but this needs investigation. Any losses should be shared fairly.

TODO: Gas golf by adding some "unchecked" when we know its impossible. better to wait until the end on that since things might get moved around. It's also probably more dangerous than its worth. But we should do some basic gas golfing.

TODO: What happens if 100% of the tokens are burned/sponsored after there is some liquidity in the system? I have a test for this, but I want more.

TODO: Someone can send us a single wei of a token and then start an auction. That auction will probably fail. This will waste a day of our time. Possible solution: if the kickable balance is 100x the current balance, allow cancelling the auction. That might open a griefing attack. 

TODO: Before deploying, make sure the code does not contain any "TODO: remove before flight"

## Miscellaneous Ideas and Todos

Primarily, this project gives me a reason to play with some smart contract tools/frameworks to prepare for a more serious project.

If someone does a dust attack and then kicks an auction, they might be able to do some trickery with the deposit queue. This forces the deposit queue to be 3 days long. (so that theres time for 2 auctions and some buffer).

The fan token owner can create the token with any name and symbol and fees that they want. But these settings cannot be changed. I don't want someone changing the symbol of their token to USDC and confusing people that already hold it.

The owner can transfer ownership but they cannot change the treasury address.

I tend towards having everything be immutable. If you want to change something, just deploy a new fan token. Users can migrate if they wish.

A fan token is like a branded [PoolTogether](https://pooltogether.com/) ticket.

I don't know what to call this exactly. The terms "creator token" and "social token" are being experimented with. I like "fan token".

There are no deposit or withdrawal fees on the fan.

In order to prevent shenanigans after winning a large prize, there is a 2 day delay on deposits.

I want the tip to be valuable in some way, but I really do not want people to buy my token and push a price curve around. Having to provide liquidity and deal with price curves and such just doesn't feel good to me.

So what's an alternative? Backing! My fan token is backed by deposits in pooltogether. This stops me from just minting 1 billion and giving them out freely, but I think some value attached will work.

If you want to support me, holding my token is an easy way. If you don't care about holding my token, you can redeem it for the backing tokens.

[PoolTogether](https://dev.pooltogether.com/protocol/design/) is a perfect fit because it adds some fun to small amounts of money and encourages savings.

I can't decide if I should back the token with ETH or with USDC prize pools. The APY on the ETH pools is a lot smaller. But encouraging savings of ETH is probably better in the long term. The prizes are in ETH no matter what the prize pool takes for deposits.

Harvest fees can be configured by the token creator with the only constraint being that owner fees plus treasury fees cannot exceed 100%.

Prizes and rewards are distributed with [Empire Builder](https://farcaster.xyz/miniapps/x7DwM6UhLXps/empire-builder). The contract owner gets a configurable percentage of any prizes or rewards, with the remainder distributed among token holders.

A previous version was designed to not have any value. Whoever held the most could set a billboard. I think a dedicated "Billboard" contract makes more sense.

An old version of the token had a "billboard". Whoever held the most tokens, could set the string. I don't like having the ability to erase the billboard. But it seems like that's a good idea for this experiment. That worked when I gave the BRY out, but the new design is backed and I don't think that works as well.

A decaying price on the billboard is an interesting idea.

Most systems that allow crypto posting like this burn the tokens when someone writes. But I don't like burns.

allow signatures for claiming and for transfers (permit2).

a billboard contract that can be set by whoever has participated in the most prize winnings. will need to track winnings very differently for that to work though.

a migrator contract that converts from b1 to b2 to b3

should this be a 4626 vault? things are 1:1 when everything works, but what if something goes wrong. i think 4626 has a bunch of protections for that. though maybe a wrapped ERC20 would be fine.

uniswap v4 hooks are giving me headaches. there is a list of approved hooks somewhere. maybe the constant-sum hook will work well enough to start.

Should there be an "opt-out" option that automatically redeems during a transfer?

I need an example bot for handling the dutch auctions. Yearn is already running infrastructure for these though so I we get that for "free".

I need an example bot for calling harvest.

I need a mini-app for managing deposits and redeems. Also for deploying your own tokens. And seeing the pooltogether odds for the token.

Should fan tokens be able to hold NFTs? we'll need some ERC165 things

Allow cancelling a pending deposit?

New Auction Factory: https://etherscan.io/address/0xbC587a495420aBB71Bbd40A0e291B64e80117526#code

## Further Reading

- [Yearn's Dutch Auctions](https://github.com/yearn/tokenized-strategy-periphery/blob/master/src/Auctions/Auction.sol)
- [PoolTime](https://farcaster.xyz/miniapps/T97hT9WJH64p/pooltime) - A PoolTogether mini-app
- [Noice](https://farcaster.xyz/miniapps/jzc2pVtLe_oa/noice)
- [Cobuild](https://farcaster.xyz/miniapps/XTipkfp9jZBu/cobuild)
- [Empire Builder](https://farcaster.xyz/miniapps/x7DwM6UhLXps/empire-builder)

## Developer Documentation

<https://book.getfoundry.sh/>

### Dependencies

```shell
brew install lcov
```

### Build

```shell
forge build
```

### Test

```shell
./script/test.sh -vvv
```

### Format

```shell
forge fmt
```

### Code Coverage

Run the tests with coverage and generate the report:

```shell
./script/test.sh coverage
```

### Gas Snapshots

```shell
./script/test.sh snapshot
```

### Anvil

```shell
./script/test.sh anvil
```

### Deploy on a Forked Network

First, start the "anvil" rpc server:

```shell
./script/test.sh anvil
```

That will start anvil and then run the deploy scripts for the factory and the "Bryan" fan tokens for you.

Anvil will be configured to use chain id 31337. It will run at <http://127.0.0.1:8545>.


### Deploy on a Live Network

First, set up an account:

```shell
cast wallet import --help
```

```shell
cast wallet import \
    <your_account_name> \
    --mnemonic \
    --mnemonic-index \
;
```

Run the deploy script against a live network:

```shell
source .env
```

```shell
./script/deploy_fan_token_factory.sh \
    --account "$ACCOUNT" \
    --rpc-url "$BASE_RPC_URL" \
    --verify \
    --verifier etherscan
```

```shell
./script/deploy_bryan.sh \
    --account "$ACCOUNT" \
    --rpc-url "$BASE_RPC_URL" \
    --verify \
    --verifier etherscan
```

### Cast

```shell
cast <subcommand>
```

### Help

```shell
forge --help
```

```shell
anvil --help
```

```shell
cast --help
```
