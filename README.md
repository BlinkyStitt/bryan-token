## Bryan Token

A token that Bryan can gift. This is only a toy.

## Developer Documentation

<https://book.getfoundry.sh/>

## Usage

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

# Ideas

- I don't like having the ability to erase the billboard. But it seems like that's a good idea for this experiment.

- A decaying price on the billboard is an interesting idea.

- Most systems like this burn the tokens when someone writes. But I don't like burns. And

- allow signatures for claiming and for transfers (permit2).

- a script that makes it easy to call "yoink" to set the billboard

- a migrator contract that converts from b1 to b2 to b3

- should this be a 4626 vault? things are 1:1 when everything works, but what if something goes wrong?
