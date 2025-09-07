// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {FanToken, FanTokenFactory, IERC20, IERC4626, IWETH9} from "../src/FanTokenFactory.sol";
import {console} from "forge-std/console.sol";

contract FanTokenFactoryTest is Test {
    IERC4626 prizeVault;
    FanToken public bryan;
    FanTokenFactory public fanTokenFactory;

    address treasury;
    IWETH9 weth;

    function setUp() public {
        weth = IWETH9(address(0x4200000000000000000000000000000000000006));

        fanTokenFactory = new FanTokenFactory(weth);

        // TODO: use flags on the test command instead of forcing a fork here?
        address owner = makeAddr("bryan owner");

        prizeVault = IERC4626(0x4E42f783db2D0C5bDFf40fDc66FCAe8b1Cda4a43);

        // TODO: need tests that have fees!
        uint256 harvestOwnerFeeBasisPoints = 0;
        uint256 harvestTreasuryFeeBasisPoints = 0;
        treasury = makeAddr("treasury");
        uint256 initialDeposit = 0 ether;

        bytes32 salt = bytes32(0);

        vm.prank(owner);
        bryan = fanTokenFactory.create(
            "ETH from Bryan",
            "BRY-ETH",
            1 days,
            harvestOwnerFeeBasisPoints,
            harvestTreasuryFeeBasisPoints,
            prizeVault,
            treasury,
            salt,
            initialDeposit
        );
    }

    function test_initial_deposit() public {
        uint256 initialDeposit = 1 ether;

        FanToken fanToken = fanTokenFactory.create{value: initialDeposit}(
            "ETH from Bryan Again", "BRY-ETH-2", 1 days, 0, 0, prizeVault, address(0), bytes32(0), initialDeposit
        );

        assertEq(fanToken.balanceOf(address(this)), initialDeposit, "initial deposits should be 1:1");

        assertEq(
            fanToken.balanceOfUnderlying(address(this)),
            initialDeposit,
            "balance of underlying from initial deposit is incorrect"
        );
    }

    function test_vault_asset() public {
        require(address(bryan.underlying()) == address(weth));
    }

    function test_factory_payable_deposit() public {
        deal(address(this), 1 ether);

        address receiver = makeAddr("receiver");

        uint256 shares = fanTokenFactory.startDeposit{value: 1 ether}(bryan, 1 ether, receiver);

        prizeVault = IERC4626(bryan.asset());

        // TODO: what should the amounts actually be?
        assertGt(bryan.balanceOf(receiver), 0, "receiver should have a balance");
        assertGt(prizeVault.balanceOf(address(bryan)), 0, "token should have a balance");
        // TODO: make sure some fees went to the owner
        // TODO: check on the fees going to the owner
        // TODO: check on the fees going to the treasury

        // TODO: test fees! I want this fee to be sent as bryan, not as prizeVault!
        // assertGt(prizeVault.balanceOf(bryan.owner()), 0);
    }

    function test_factory_deposit_and_withdraw() public {
        // TODO: for some reason we can't deal the ERC4626. We can deal the ERC20 though.
        uint256 underlyingAssets = 1_000 * 1e6;

        IERC20 underlying = bryan.underlying();
        deal(address(underlying), address(this), underlyingAssets, false);

        // test the factory's deposit function
        underlying.approve(address(fanTokenFactory), type(uint256).max);
        uint256 shares = fanTokenFactory.startDeposit(bryan, underlyingAssets, address(this));

        console.log("shares:", shares);

        IERC4626 asset = IERC4626(bryan.asset());
        uint256 assets = bryan.previewRedeem(shares);

        // TODO: this require is wrong. we want to be sure that the shares we received are worth what we deposited
        // require(assets == shares);

        // TODO: the fees make this annoying. TODO: I'm also not sure these are even the right checks. think about these more
        assertGt(asset.balanceOf(address(bryan)), 0, "asset balance does not match assets");
        assertEq(bryan.balanceOf(address(this)), shares, "bryan balance does not match shares");

        // test the main redeem function
        // TODO: send to a "receiver" address just to make the accounting clean?
        bryan.approve(address(fanTokenFactory), type(uint256).max);
        uint256 redeemed = fanTokenFactory.redeem(bryan, shares, address(this));

        // TODO: the fees make this annoying. TODO: I'm also not sure these are even the right checks. think about these more
        assertGt(redeemed, 0, "none redeemed"); // TODO: what should this amount be?
        assertEq(IERC20(bryan.asset()).balanceOf(address(bryan)), 0, "token's asset balance should be empty");
        assertEq(bryan.balanceOf(address(this)), 0, "our balance of bryan should be empty");

        // TODO: something feels wrong about this amount. we should be able to use assertEq here, but we have slightly more tokens than expected
        assertGt(
            underlying.balanceOf(address(this)),
            underlyingAssets * 99 / 100,
            "we should have our asset back (less the deposit fee)"
        );
    }
}
