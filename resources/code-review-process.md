# Code Review Porcess: Four-Level Comprehension Framework

## Level 1: Literal Comprehension (Code Syntax)

At this level, you're understanding what the code literally does - the basic syntax and function calls. The **smart skimming** strategy is particularly powerful here:

- **Skim for critical patterns**: Instead of reading every line linearly, scan for security-sensitive patterns like `delegatecall`, `selfdestruct`, `transfer`, `send`, external calls, state changes, and access modifiers
- **Focus on high-risk areas**: Slow down at functions handling funds, ownership changes, or complex math operations
- **Identify entry points**: Quickly map out external/public functions that attackers could interact with

This gives you a rapid overview of the attack surface without getting bogged down in implementation details.

## Level 2: Implied Comprehension (Understanding Intent)

Here you're reading between the lines - understanding not just what the code does, but what the developers *intended* it to do:

- **Protocol assumptions**: What invariants are the developers assuming will hold?
- **Trust boundaries**: Where does the code assume honest behavior vs adversarial behavior?
- **Economic mechanisms**: Understanding the tokenomics or financial incentives beyond just the code

The **immersion** strategy applies here - the more smart contracts you review, the faster you'll recognize common patterns and anti-patterns.

## Level 3: Critical Comprehension (The Bug Hunter's Edge)

This is where you gain a massive advantage. The **question and critique** strategy becomes your vulnerability discovery engine:

**Key Questions for Each Function:**
- "Why did they implement it this way instead of using a standard pattern?"
- "What assumptions could break under edge cases?"
- "How could this interact badly with other functions?"
- "What happens if this is called in an unexpected order?"
- "Could this be front-run or sandwich attacked?"

**Critical Analysis Points:**
- Compare against known vulnerability patterns (reentrancy, integer overflow, etc.)
- Question every external dependency and oracle
- Critique the access control model
- Challenge the upgrade mechanism if present

Taking deliberate pauses to think through attack vectors is MORE valuable than quickly reading through more code. This is the "bottleneck flip" - your limiting factor isn't how fast you read code, but how deeply you analyze it.

## Level 4: Adaptive Comprehension (Exploit Development)

This is where you synthesize everything to craft actual exploits:

### Abstract
Extract the core vulnerability pattern from the specific implementation:
- "This is essentially a reentrancy variant"
- "This follows the same pattern as the XYZ hack"
- "This is a novel composition of known issues"

### Apply
Develop proof-of-concept exploits:
- Write test cases that demonstrate the vulnerability
- Calculate potential damage/funds at risk
- Consider how this could be chained with other issues
- Test your assumptions on testnet/local fork

### Attack
Challenge your own findings:
- "Could there be mitigating factors I missed?"
- "Would this work on mainnet with real gas prices and MEV?"
- "Are there external dependencies that could prevent this?"
- Use tools like ChatGPT or forums to stress-test your logic

## Practical Implementation

**For a typical bug bounty review:**

1. **First pass (Level 1)**: 30 minutes of smart skimming to map the codebase and identify high-risk areas

2. **Deep dive (Level 3)**: Spend 2-3 hours on critical functions, constantly questioning and critiquing. This is where most bugs are found.

3. **Exploit development (Level 4)**: 1-2 hours building PoCs for suspected vulnerabilities

4. **Validation**: Test extensively and seek counterarguments

The key insight is that reading 1000 lines of code at Level 1-2 comprehension will find far fewer bugs than reading 100 lines at Level 3-4 comprehension. The developers who wrote the code operated at Level 2 - they understood what they wrote. As a bug hunter, you need to operate at Level 3-4, questioning everything they took for granted.

This approach transforms you from someone who just "reads code fast" into someone who "thinks like an attacker" - and that's what wins bug bounties.
