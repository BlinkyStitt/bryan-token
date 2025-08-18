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
