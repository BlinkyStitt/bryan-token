# Bryan's Tokens

A "fan token" that is backed. No pump and dump games here.

## Warning!

- This is an experiment and a toy, not a financial investment.
- This is not audited.

## What is this?

Primarily, I am playing with tools to prepare for a more serious project.

I don't know what to call this. The terms "creator token" and "social token" are being experimented with.

I don't want to just tip out USDC or WETH. I want to be able to send something more personalized.

I want the tip to be valuable in some way, but I really do not want people to buy my token and push a price curve around. Having to provide liquidity and deal with price curves and such just doesn't feel good to me.

So what's an alternative? Backing! My fan token is backed by deposits in pooltogether. This stops me from just minting 1 billion and giving them out freely, but I think some value attached will work.

If you want to support me, holding my token is an easy way. If you don't care about holding my token, you can redeem it for the backing tokens.

Pooltogether is a perfect fit because it adds some fun to small amounts of money and encourages savings.

I can't decide if I should back the token with ETH or with USDC prize pools. The APY on the ETH pools is a lot smaller. But encouraging savings of ETH is probably better in the long term. The prizes are in ETH no matter what the prize pool takes for deposits.

## Miscellaneous Ideas

- A previous version was designed to not have any value. Whoever held the most could set a billboard. I think a dedicated "Billboard" contract makes more sense.

- I don't like having the ability to erase the billboard. But it seems like that's a good idea for this experiment.

- A decaying price on the billboard is an interesting idea.

- Most systems that allow crypto posting like this burn the tokens when someone writes. But I don't like burns.

- allow signatures for claiming and for transfers (permit2).

- a script that makes it easy to call "yoink" to set the billboard

- a migrator contract that converts from b1 to b2 to b3

- should this be a 4626 vault? things are 1:1 when everything works, but what if something goes wrong. i think 4626 has a bunch of protections for that. though maybe a wrapped ERC20 would be fine.

## Further Reading

- <https://github.com/yearn/tokenized-strategy-periphery/blob/master/src/Auctions/Auction.sol>
- [Pool together](https://dev.pooltogether.com/protocol/design/)

## Developer Documentation

<https://book.getfoundry.sh/>

### Build

```shell
forge build
```

### Test

```shell
forge test
```

### Format

```shell
forge fmt
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
