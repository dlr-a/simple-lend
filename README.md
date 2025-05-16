# 🧾 SimpleLend Protocol

## 🛠️ Overview

**SimpleLend** is a minimalistic decentralized lending protocol that allows users to:

- Supply ERC20 tokens to earn interest
- Deposit ERC20 tokens as collateral
- Borrow other ERC20 tokens by paying interest
- Repay their debt
- Withdraw their collateral
- Be liquidated if undercollateralized

---

## ⚙️ Features

- ✅ Supply ERC20 tokens to earn interest
- ✅ Deposit ERC20 tokens as collateral
- ✅ Borrow against your collateral
- ✅ Health Factor & liquidation mechanism
- ✅ ERC20-compliant `SToken` for tracking deposits
- ✅ Fuzz & invariant tested with Foundry

---

## 🔧 Technologies Used

- [Solidity](https://docs.soliditylang.org/en/v0.8.0/) ^0.8.x
- [Foundry](https://book.getfoundry.sh/) (Forge, Anvil, Cast)
- Chainlink Price Feed (mocked locally)
- ERC20 standards

---

## 📦 Installation

````bash
git clone https://github.com/dlr-a/simple-lend.git
cd simple-lend
forge install
forge build


### Build

```shell
$ forge build
````

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/DeploySimpleLend.s.sol:DeploySimpleLend --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
