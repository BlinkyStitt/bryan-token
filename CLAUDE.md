## Feature Implementation System Guidelines

### Feature Implementation Priority Rules
- IMMEDIATE EXECUTION: Launch parallel Tasks immediately upon feature requests
- NO CLARIFICATION: Skip asking what type of implementation unless absolutely critical
- PARALLEL BY DEFAULT: Always use 3-parallel-Task method for efficiency

### Memories

- Do not use `forge test` directly. Instead, run tests with `./script/test.sh [test|coverage|snapshot]`! you can pass flags through to the forge test command
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
