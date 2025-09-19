## Feature Implementation System Guidelines

### Feature Implementation Priority Rules
- IMMEDIATE EXECUTION: Launch parallel Tasks immediately upon feature requests
- NO CLARIFICATION: Skip asking what type of implementation unless absolutely critical
- PARALLEL BY DEFAULT: Always use 7-parallel-Task method for efficiency
- TESTING: Do not use `forge test` directly! Instead, run tests with `./script/test.sh test`! you can pass flags through to the forge test command
- ONE TEST: To run one test, do `./script/test.sh -vvv --match-test THE_ONE_TEST`
- COVERAGE: Do not use `forge coverage` directly. Instead, run tests with `./script/test.sh coverage`! You can pass flags through to the forge coverage command. If tests pass, the html coverage report will be created.
- GAS USAGE SNAPSHOT: Do not use `forge snapshot` directly. Instead, run tests with `./script/test.sh snapshot`! you can pass flags through to the forge snapshot command

- AGAIN: Do not use `forge test` directly! Use the helper script!

### Memories

- If all tests pass, you can generate coverage by running `./script/test.sh coverage` and then `genhtml lcov.info --output-dir coverage`
- Keep functions and imports in alphabetical order. but only within groups (immutables, state vars, events, errors, internal, public, external, etc.)
- follow open zeppelin's standards
- Remember to run `forge fmt` and `forge lint` to keep the code clean
- you should see yourself as a novice developer. Be sure to check docs thoroughly rather than guess.
- Tests should assert expected values and not just confirm that the calls don't revert
- An "Unused local variable" is always bad. It means you probably forgot to check something. 
- You don't need so many `vm.stopPranks`. they dont do anything useful at the end of a test. and they dont do anything useful if you prank/startPrank right after 
  them
- `git commit` and `git push` your code often

### Feature Implementation Guidelines
- **CRITICAL**: Make MINIMAL CHANGES to existing patterns and structures
- **CRITICAL**: Preserve existing naming conventions and file organization
- Follow project's established architecture and component patterns
- Use existing utility functions and avoid duplicating functionality

### Security Guidelines
- ALWAYS check for reentrancy vulnerabilities - use nonReentrant modifier or CEI pattern
- VALIDATE all external calls and handle failures appropriately
- CHECK for integer overflow/underflow (even with Solidity 0.8+, consider SafeMath patterns)
- VERIFY access controls on all state-changing functions
- ENSURE proper input validation (zero addresses, array bounds, etc.)
- CHECK for front-running vulnerabilities in price-sensitive operations
- VALIDATE external contract interactions and handle reverts

### Common Vulnerability Checks
- Reentrancy attacks (check all external calls)
- Access control bypasses (verify onlyOwner, onlyRole patterns)
- Integer arithmetic issues (check for potential overflows in calculations)
- Denial of service via gas limit manipulation
- Flash loan attacks in DeFi protocols
- Sandwich attacks on DEX operations
- Oracle manipulation vulnerabilities

### Gas Optimization Patterns
- Use packed structs when possible
- Prefer uint256 over smaller uint types for gas efficiency
- Cache storage variables in memory for repeated access
- Use events instead of storage for data that doesn't need on-chain queries
- Consider using assembly for gas-critical operations

### Smart Contract Documentation
- ALWAYS include NatSpec comments (@dev, @param, @return)
- Document invariants and assumptions clearly
- Explain complex mathematical operations step-by-step
- Include examples of expected usage patterns

### Testing Requirements
- When writing tests do not change application code.
- When fixing failing tests, do not change test code.
- Test all edge cases (zero values, max values, boundary conditions)
- Include fuzzing tests for mathematical operations
- Test access control restrictions thoroughly
- Verify events are emitted with correct parameters
- Test integration scenarios with external contracts
- Include gas consumption tests for critical functions

### MEV Protection & Economic Security
- CHECK for sandwich attack vulnerabilities in AMM operations
- VERIFY slippage protection in DEX interactions
- ANALYZE for flash loan arbitrage attack vectors
- REVIEW token economics for inflation/deflation exploits
- CHECK for governance token voting manipulation
- VERIFY time-lock mechanisms on critical parameter changes
- ANALYZE cross-chain bridge vulnerabilities

### State Consistency Checks
- VERIFY state transitions follow expected business logic
- CHECK for race conditions in multi-step operations
- ENSURE atomic operations where required (all-or-nothing)
- VALIDATE state machine transitions are properly gated
- CHECK for storage collision issues in proxy patterns
- VERIFY initialization can only happen once
- ENSURE proper cleanup in failure scenarios

### DeFi Protocol Auditing
- VERIFY oracle price feeds are properly validated and have circuit breakers
- CHECK for yield farming reward calculation errors
- ANALYZE liquidation mechanisms for edge cases
- VERIFY collateral ratio calculations handle all scenarios
- CHECK for protocol fee extraction vulnerabilities
- ANALYZE governance proposal execution safeguards

### Token Standards Compliance
- VERIFY ERC-20/721/1155 standard compliance
- CHECK for transfer hooks and callback vulnerabilities
- ENSURE proper approval/allowance handling
- VERIFY metadata immutability where required

### Systematic Audit Approach
1. ARCHITECTURE REVIEW: Understand system design and trust assumptions
2. CODE WALKTHROUGH: Line-by-line review of critical functions
3. INVARIANT ANALYSIS: Identify and test system invariants
4. ATTACK VECTOR MAPPING: Systematically check each vulnerability class
5. INTEGRATION TESTING: Test interactions with external protocols
6. ECONOMIC ANALYSIS: Model token economics and incentive structures
