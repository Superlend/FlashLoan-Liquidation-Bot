## FlashLoan Liquidation Bot

-   **src/flashLiquidations.sol**: Contract for carrying out liquidation using Flashloan and routing swap through IguanaDEX.
-   **script/DeployContract.s.sol**: Contract deployment script.
-   **script/TestLiquidation.s.sol**: Script for carrying out liquidation on deployed contract, please change the values for tokens and user to liquidate as per need.
-   **test/***: Contains test cases for carrying out liquidation.

## Documentation

- Please setup **PRIVATE_KEY** value in env.

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Deploy

```shell
$ forge script script/DeployContract.s.sol --skip-simulation --broadcast --verify
```

### Test liquidation

```shell
$ forge script script/TestLiquidation.s.sol --broadcast --skip-simulation
```

### Help

```shell
$ forge --help
```
