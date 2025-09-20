# TODO Analysis - Organized by Priority

## ✅ COMPLETED TODOs (to be removed)

1. **FanTokenFactory.sol:75** - "set up the uniswap v4 pool for making trades transparently" - ✅ **DONE** - We implemented `_setupUniswapV4HookedPool()` function

## 🔥 HIGH PRIORITY - Critical Issues

### Architecture & Core Functionality
1. **FanToken.sol:186** - "i think this transfer is broken. i think when it happens," - Incomplete comment indicates potential critical bug in redeem function
2. **FanToken.sol:286-288** - Handle excess tokens when deposits exceed maxDepositAssets, emit events about stuck tokens
3. **README.md:30** - Ensure sponsors can't take unfair share during vault losses - critical fairness issue
4. **README.md:36** - Prevent griefing attacks from single wei auctions that will fail

### Gas & Performance
1. **FanToken.sol:4** - Use cloneable instead of deploying full contract every time (significant gas savings)
2. **FanTokenFactory.sol:171** - Do infinite approval when fan token is deployed instead of per-transaction
3. **README.md:32** - Gas golf with unchecked blocks where overflow impossible

### Security & Validation
1. **FanToken.sol:248** - Store minimum trade amount for auctions, consider making enableAuction owner-only
2. **FanToken.sol:133** - Add _transfer override to prevent users from calling transfer to factory

## 🚨 MEDIUM PRIORITY - Important Features

### Missing Core Features
1. **FanTokenFactory.sol:195-196** - Implement mint() and withdraw() functions for completeness
2. **FanToken.sol:512-514** - Implement sponsorTransferFrom and sponsor operator mapping
3. **FanToken.sol:311** - Mint fan tokens for treasury fees instead of transferring vault shares directly

### Deposit/Withdrawal System
1. **FanTokenFactory.sol:105** - Solve async deposit problems for one trade direction with hooks
2. **FanToken.sol:74** - Include nonce in pendingDepositOf to prevent multiple deposits resetting timer
3. **FanToken.sol:155** - Decide if first deposit should check `totalPendingAssets == 0`

### Event & Monitoring
1. **FanToken.sol:429** - Emit events for sponsorship changes
2. **README.md:38** - Consider having contract claim pool prizes automatically

## ⚠️ LOW PRIORITY - Nice to Have

### Code Quality & Organization
1. **FanToken.sol:51** - Better name for TREASURY constant
2. **FanToken.sol:88** - Change constructor into initializer that can only run once
3. **FanTokenFactory.sol:37** - Decide how to index the Created event
4. **FanToken.sol:319** - DRY principle - treasury and owner fee code is duplicated

### Testing & Development
1. **test/FanTokenFactory.t.sol:30** - Add tests that have fees
2. **test/FanToken.t.sol:653,759** - Use factory.create() instead of pranking factory in tests
3. Multiple test TODOs about specific balance amounts and transfer scenarios

### Interface & Usability
1. **FanToken.sol:540,545** - Remove unnecessary totalSponsoredShares/Assets functions if not needed
2. **IFanToken.sol:27,29** - Clarify if we need totalPendingAssets and totalSponsorAssets functions

### Development Tooling
1. **script/Bryan.s.sol:8** - Rewrite script to prompt for inputs instead of hard coding
2. **script/FanTokenFactory.s.sol:53** - Add script to prompt for create() function params
3. **test files** - Use flags instead of forcing fork in tests

## 🗑️ QUESTIONABLE - Needs Discussion

### Design Decisions
1. **FanToken.sol:106** - "i can't decide if this should have one" - fee basis points validation
2. **FanToken.sol:125** - "this should maybe be optional" - automatic treasury sponsorship
3. **FanToken.sol:129-132** - Whether fan token contract itself should be sponsor, factory should be sponsor
4. **FanToken.sol:393-395** - Sponsorship system design decisions (time lock, separate contract, etc.)
5. **FanToken.sol:78** - Whether tracking balanceOfPending is worth the gas cost

### Test Quality
1. Many test TODOs asking "what should this amount be?" - indicates unclear expected behavior
2. Transfer test scenarios that are commented out but not implemented

## 📊 STATISTICS
- **Total TODOs found:** ~85+ (excluding library dependencies and coverage HTML)
- **Completed:** 1
- **High Priority:** 9 items
- **Medium Priority:** 8 items
- **Low Priority:** 15+ items
- **Questionable/Discussion needed:** 8+ items

## 🎯 RECOMMENDED NEXT STEPS
1. Fix the broken transfer in redeem function (HIGH)
2. Implement cloneable factory pattern (HIGH - big gas savings)
3. Add minimum auction amounts to prevent griefing (HIGH)
4. Handle vault loss scenarios fairly (HIGH)
5. Add missing mint/withdraw functions (MEDIUM)