# Fan Tokens

I want to send tips to people using cryptocurrency, but I don't want to just tip out USDC or ETH. I want to be able to send something more personalized. So I made "fan tokens" as a kind of wrapping paper around these other tokens.

Hold a fan token if you like the owner.

Every day, [PoolTogether prizes](https://pooltogether.com/) might go out to all of the fan token holders.

You shouldn't buy this token. This token is meant to be given as a gift. If you have any, it's probably from an interaction with the owner on farcaster.

Fan tokens can be created for free by depositing pooltogether tickets.

If you received some fan tokens and don't want to participate in the game, you can return them for the backing pooltogether tickets (which are themselves backed by valuable tokens like ETH or USDC).

## Warning!

- This is an experiment and a toy.
- This is not audited.

## Design

Can't be evil is my foundational principle for smart contract development. That means contracts should be immutable and functions should not be restricted to privileged users.

No pump and dump games here. Backing means we don't need to provide liquidity on an AMM.

If something would be nice to change but could be abused, then make it impossible to change. For example, I would like to be able to change the name and symbol for my token. But that can be abused. So it's immutable for my contracts.

## Miscellaneous Ideas and Todos

Primarily, this project gives me a reason to play with some smart contract tools/fras]meworks to prepare for a more serious project.

The fan token owner can create the token with any name and symbol and fees that they want. But these settings cannot be changed.

The owner can transfer ownership but not change the treasury address.

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

Deposit fees can be set between 0% and 20%. I'm going to start at 1%.

Prizes and rewards will be distributed with [Empire Builder](https://farcaster.xyz/miniapps/x7DwM6UhLXps/empire-builder). The contract owner (flashprofits.eth) will get 50% of any prizes or rewards (this can be set between 0% and 90%). The top 100 holders of BRY will split the other 50%.

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

## Further Reading

- <https://github.com/yearn/tokenized-strategy-periphery/blob/master/src/Auctions/Auction.sol>
- [PoolTime](https://farcaster.xyz/miniapps/T97hT9WJH64p/pooltime) - A PoolTogether mini-app
- [Noice](https://farcaster.xyz/miniapps/jzc2pVtLe_oa/noice)
- [Cobuild](https://farcaster.xyz/miniapps/XTipkfp9jZBu/cobuild)

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

Run the tests with coverage:

```shell
forge coverage --fork-url https://1rpc.io/base --report lcov
```

Generate the report:

```shell
genhtml lcov.info --output-dir coverage
```

### Gas Snapshots

```shell
forge snapshot
```

### Anvil

```shell
anvil
```

### Deploy

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

Run the deploy script against a forked network:

```shell
forge script Bryan --fork-url <your_rpc_url> --account <your_account_name>
```

Run the deploy script against a live network:

```shell
forge script Bryan --rpc-url <your_rpc_url> --account <your_account_name>
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
