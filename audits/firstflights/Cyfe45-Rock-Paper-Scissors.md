# Rock Paper Scissors - Findings Report

# Table of contents
- ## [Contest Summary](#contest-summary)
- ## [Results Summary](#results-summary)
- ## High Risk Findings
    - ### [H-01. Insufficient game state tracking causing potential multiple playerB entrants](#H-01)
    - ### [H-02. Unchecked transfer in `joinGameWithToken` causing games to start without properly transferring tokens from the player](#H-02)

- ## Low Risk Findings
    - ### [L-01. Incorrect use of mint function during refunds in game cancellation and tie scenarios causing loss of staked totekns](#L-01)


# <a id='contest-summary'></a>Contest Summary

### Sponsor: First Flight #38

### Dates: Apr 17th, 2025 - Apr 24th, 2025

[See more contest details here](https://codehawks.cyfrin.io/c/2025-04-rock-paper-scissors)

# <a id='results-summary'></a>Results Summary

### Number of findings:
- High: 2
- Medium: 0
- Low: 1


# High Risk Findings

## <a id='H-01'></a>H-01. Insufficient game state tracking causing potential multiple playerB entrants            



## Summary

In both the `joinGameWithEth` and `joinGameWithToken` there is insufficient updating of the game state leading to potential multiple entrants causing confusion as to who is actually playing the game.

## Vulnerability Details

The RockPaperScissors game does not cater for different game states resulting in potential multiple of playerB entrants. This is due to both the `joinGameWithEth` and `joinGameWithToken` there is insufficient updating of the game state leading to potential multiple entrants causing confusion as to who is actually playing the game.

Affected code:

**joinGameWithEth:**
```solidity
    function joinGameWithEth(uint256 _gameId) external payable {
        Game storage game = games[_gameId];

        require(game.state == GameState.Created, "Game not open to join");
        require(game.playerA != msg.sender, "Cannot join your own game");
        require(block.timestamp <= game.joinDeadline, "Join deadline passed");
        require(msg.value == game.bet, "Bet amount must match creator's bet");

        game.playerB = msg.sender;
        emit PlayerJoined(_gameId, msg.sender);
    }
```

**joinGameWithToken:**
```solidity
    function joinGameWithToken(uint256 _gameId) external {
        Game storage game = games[_gameId];

        require(game.state == GameState.Created, "Game not open to join");
        require(game.playerA != msg.sender, "Cannot join your own game");
        require(block.timestamp <= game.joinDeadline, "Join deadline passed");
        require(game.bet == 0, "This game requires ETH bet");
        require(winningToken.balanceOf(msg.sender) >= 1, "Must have winning token"); // @audit how does this check work?

        // Transfer token to contract
        winningToken.transferFrom(msg.sender, address(this), 1);
        game.playerB = msg.sender;
        emit PlayerJoined(_gameId, msg.sender);
    }
```

## Impact

Severity: High
Impact: High, as it could potentially put people off from playing the game
Likelihood: Medium, depending on popularity of the game and "malicious" players wanting to steal the game

## Tools Used

Manual review of codebase.

## Recommendations

**Implement Atomic State Updates and Status Checks:**

```solidity
function joinGameWithEth(uint256 _gameId) external payable {
    // ...existing validations...
require(
    game.state == GameState.Created || game.state == GameState.Joined,
    "Invalid state transition"
);

    // State updates
    game.playerB = msg.sender;
    game.state = GameState.Joined;
    game.startTime = block.timestamp; 
    game.currentTurn = 1; // Initialize turn counter
    
    emit PlayerJoined(_gameId, msg.sender);
}
```


## <a id='H-02'></a>H-02. Unchecked transfer in `joinGameWithToken` causing games to start without properly transferring tokens from the player            



## Summary

The `joinGameWithToken` function performs an unsafe ERC20 token transfer that does not validate the success of the operation. This could allow games to start without properly transferring tokens from the player, leading to inconsistent protocol states and potential loss of funds.

## Vulnerability Details

**Affected Code**:

```solidity
function joinGameWithToken(uint256 _gameId) external {
    // ...validations...
    winningToken.transferFrom(msg.sender, address(this), 1); // No success check
    game.playerB = msg.sender; // State updated even if transfer failed
}
```

**Root Cause**:\
The `transferFrom` function returns a boolean indicating success, but this value is never checked. If the token transfer fails (e.g., insufficient allowance/balance), the function:

1. Proceeds as if the transfer succeeded
2. Updates the game state (`playerB`)
3. Allows the game to start with invalid token custody

## Impact

**Severity**: High\
**Likelihood**: Medium (Depends on token implementation)\
**Consequences**:

* Games starting without token collateral
* Players participating without staking tokens
* Protocol accounting inconsistencies

## Tools Used

1. **Manual Review**: Identified unchecked `transferFrom` call
2. **Slither**: Flagged unchecked return value (Detector ID: `unchecked-transfer`)

## Recommendations

Add explicit success checks for token transfers:

```solidity
function joinGameWithToken(uint256 _gameId) external {
    // ...validations...
    
    bool success = winningToken.transferFrom(msg.sender, address(this), 1);
    require(success, "Token transfer failed"); // Critical check
    
    game.playerB = msg.sender; // Safe state update
}
```

    


# Low Risk Findings

## <a id='L-01'></a>L-01. Incorrect use of mint function during refunds in game cancellation and tie scenarios causing loss of staked totekns            



## Summary

The protocol incorrectly handles token refunds in game cancellation and tie scenarios by minting new tokens instead of returning staked tokens. This results in permanent loss of originally staked tokens and unintended token supply inflation.

## Vulnerability Details

**Affected Functions**:

1. `_cancelGame()` - Token refund logic
2. `_handleTie()` - Tie resolution logic

**Root Cause**:

* When cancelling games or handling ties, the contract attempts to "refund" tokens by **minting new ones** to players:

```solidity
// Incorrect implementation in _cancelGame()
winningToken.mint(playerA, 1); // Mints new token
winningToken.mint(playerB, 1); // Instead of returning originals
```

* The staked tokens remain permanently locked in the contract while new tokens are created, leading to:
  * Loss of original player tokens
  * Uncontrolled supply growth

**Code Proof**:

```solidity
// _cancelGame() snippet
if (game.bet == 0) {
    // Should TRANSFER staked tokens back
    winningToken.mint(playerA, 1); // Wrong! Creates new tokens
    winningToken.mint(playerB, 1);
}
```

## Impact

**High Severity**:

* **Direct Financial Loss**: Players never recover originally staked tokens
* **Contract Lockup**: Staked tokens become permanently inaccessible
* **Systemic Risk**: Over time, this could collapse token economics

## Tools Used

Manual review Identified mismatch between staking/minting logic.

## Recommendations

**Immediate Fix**:

1. Replace mints with transfers for refunds:

```solidity
// Corrected _cancelGame() logic
if (game.bet == 0) {
    winningToken.transfer(playerA, 1); // Return staked token
    winningToken.transfer(playerB, 1);
}
```

**Long-Term Recommendations**:

* Implement a token custody ledger to track player deposits
* Add circuit breakers for abnormal cancellation rates
* Use separate contracts for token custody vs game logic

This fix preserves token supply integrity while ensuring players recover their original assets, maintaining the protocol's economic stability.



