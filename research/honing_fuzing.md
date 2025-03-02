# Maximizing Fuzzing Efficiency in Foundry: Strategic Use of vm.assume() for Smart Contract Audits

Fuzzing is a powerful way to uncover vulnerabilities in smart contracts, but **blindly generating random inputs is inefficient**. Instead of testing meaningless values, auditors should focus on **high-risk edge cases**—where failures are most likely to occur.

This is where Foundry's `assume()` comes in. By constraining input ranges, `assume()` allows fuzzers to **prioritize execution paths that matter**. In this article, we'll explore **how to use `assume()` strategically** to maximise fuzzing efficiency in smart contract security audits.

---

## Beyond Blind Randomness: Using Probabilities to Guide Fuzzing

Most fuzzers use one of two approaches to generate inputs:

### 1. Traditional Mutation-Based Fuzzing
- Randomly modifies input data (e.g., bit flips, boundary values).
- Executes the contract and observes behaviour.
- If an assertion fails, it logs the input for debugging.

### 2. Probabilistic Model for Input Selection
- Instead of blind mutations, it assigns probabilities to input types based on past results.
- Prioritises input generation toward execution paths with higher failure likelihoods.
- Uses previous test runs to improve input selection dynamically (similar to adaptive fuzzing).

### Applying This to Smart Contract Auditing

In fuzzers like Foundry or Echidna, you can **apply this model by**:
- **Guiding Input Generation** – Target values that trigger deep execution flows (e.g., reentrancy, overflows).
- **Learning from Past Runs** – Adjust mutation strategies based on revert patterns or gas usage.
- **Optimising Path Coverage** – Focus on under-tested but high-risk functions (e.g., `delegatecall`, `selfdestruct`).

---

## Using `assume()` to Direct Foundry's Fuzzing Engine

Foundry's fuzzing engine allows us to **restrict the input space** using `assume()`, making fuzzing more **efficient and targeted**. By combining `assume()` with **historical test results**, we can create an adaptive fuzzing strategy where:
- Foundry **prioritises inputs that previously caused failures**.
- A handler injects **mutations based on execution trace probabilities**.

Now, let's explore **three key techniques** to supercharge fuzzing with `assume()`.

---

## 1. Leverage Historical Vulnerability Data

- **Context**: DeFi protocols, token contracts, or governance systems with known exploit patterns.
- **Strategy**: Use past exploits to define input ranges.

For example, if **historical hacks** involved borrowing more than **75% of a pool's liquidity**, we should **focus fuzzing in that range**:

```solidity
function test_FlashLoan(uint256 amount) public {
    uint256 maxLoan = liquidityPool.getTotalLiquidity();
    vm.assume(amount > maxLoan * 75 / 100 && amount < maxLoan);
    liquidityPool.flashLoan(amount);
}
```

**Why This Works:**
- Skips low-impact values (e.g., tiny loans).
- Focuses on critical thresholds where protocol logic might break.

## 2. Target Boundary Conditions

- **Context**: Contracts with arithmetic operations, token balances, or overflow/underflow risks.
- **Strategy**: Focus on values near dangerous boundaries like type(uint256).max, zero, or custom thresholds.

```solidity
function test_TokenOverflow(uint256 amount) public {
    vm.assume(amount > type(uint256).max - 100);
    token.transfer(address(0xdead), amount);
}
```

**Why This Works:**
- Stress-tests overflow limits.
- Surfaces issues in contracts that lack proper SafeMath protections.

## 3. Anchor Inputs to Storage State

- **Context**: Functions that depend on dynamic storage variables (e.g., collateral ratios in lending protocols).
- **Strategy**: Use real-time contract state to set input constraints.

```solidity
function test_Borrow(uint256 borrowAmount) public {
    uint256 collateral = lendingPool.getCollateral(msg.sender);
    vm.assume(borrowAmount > collateral / 2 && borrowAmount < collateral);
    lendingPool.borrow(borrowAmount);
}
```

**Why This Works:**
- Avoids nonsensical cases (e.g., borrowing 1 wei).
- Focuses on realistic failures, like undercollateralized loans.

## Quick Reference: Fuzzing Strategies at a Glance

| Technique | Example Scenario | Code Snippet |
|-----------|------------------|--------------|
| Historical Data | Flash loan liquidity thresholds | `vm.assume(amount > maxLoan * 75/100)` |
| Boundary Conditions | Integer overflow in transfers | `vm.assume(amount > type(uint256).max - 100)` |
| Storage Constraints | Borrowing against collateral | `vm.assume(borrowAmount > collateral / 2)` |

## Final Thoughts: Precision Over Randomness

Fuzzing with `assume()` transforms a scattergun approach into a sniper rifle. By applying historical insights, boundary checks, storage context, and manual biasing, smart contract auditors can:
- Reduce wasted cycles on irrelevant test cases.
- Uncover high-impact vulnerabilities faster.

The goal isn't to eliminate randomness entirely—but to guide it toward the most treacherous corners of your code.

How do you optimize fuzzing in your audits? Drop your thoughts in the comments!

Found this useful? Follow me for more smart contract security insights!
