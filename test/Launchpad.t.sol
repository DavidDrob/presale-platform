pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/StdMath.sol"; 
import "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import "src/Launchpad.sol";
import "src/Factory.sol";
import "src/Errors.sol";
import "./utils/UniswapV2Library.sol";
import "./utils/SampleData.sol";

contract LaunchPadTest is Test {
    using stdMath for uint;

	address team = makeAddr("team");
	address treasury = makeAddr("treasury");
	uint256 protocolFee = 1000; // 1% in BP

	ERC20Mock mockToken;
	Launchpad launchpad;
    LaunchpadFactory factory;

	function setUp() public {
        factory = new LaunchpadFactory(protocolFee, treasury);

        mockToken = new ERC20Mock();
        mockToken.mint(team, 100_000e18);

		// skip, so block.timestamp doesn't underflow in some tests
		skip(11 days);

		MainLaunchpadInfo memory info = SampleData._getSampleInfo(address(mockToken));
        bytes32 salt = factory.calculateSalt(team, info.name, address(info.token));
        address launchPadAddress = factory.getLaunchpadAddress(salt, info, protocolFee, treasury, team, address(factory));

		vm.startPrank(team);
        mockToken.approve(launchPadAddress, type(uint256).max);
        launchpad = Launchpad(factory.createLaunchpad(info, salt));
		vm.stopPrank();
	}

	function test_periods() public {
		assertEq(launchpad.isStarted(), false);

		skip(2 days);

		assertEq(launchpad.isStarted(), true);
		assertEq(launchpad.isEnded(), false);

		skip(5 days);

		assertEq(launchpad.isStarted(), true);
		assertEq(launchpad.isEnded(), true);
	}

	function test_updateStartDate(uint _newDate) public {
		vm.assume(_newDate < launchpad.endDate());

		vm.prank(team);
		launchpad.updateStartDate(_newDate);

		assertLt(launchpad.startDate(), launchpad.endDate());
		assertEq(launchpad.startDate(), _newDate);
	}

	function test_updateEndDate(uint _newDate) public {
		vm.assume(_newDate > launchpad.startDate());

		vm.prank(team);
		launchpad.updateEndDate(_newDate);

		assertLt(launchpad.startDate(), launchpad.endDate());
		assertEq(launchpad.endDate(), _newDate);
	}

	function test_onlyOperator() public {
		string memory nameBefore = launchpad.name();

		vm.prank(makeAddr("badActor"));
		vm.expectRevert();
		launchpad.setName("Foobar");

		assertEq(launchpad.name(), nameBefore);

		vm.prank(team);
		launchpad.setName("Foobar");
		
		assertNotEq(launchpad.name(), nameBefore);
	}

	function test_tokenAmountInLaunchpad(uint _increase) public {
		vm.assume(_increase < 100_000 ether - 1_000 ether);
		assertGe(mockToken.balanceOf(address(launchpad)), 1_000 ether);

		vm.startPrank(team);
		launchpad.increaseHardCap(_increase);

		assertGe(mockToken.balanceOf(address(launchpad)), _increase + 1_000 ether);
	}

	function test_buy(uint _amount) public {
		vm.assume(_amount >= launchpad.ethPricePerToken()
               && _amount <= launchpad.tokenToEth(launchpad.tokenHardCap()));

		address alice = makeAddr("alice");
		vm.deal(alice, type(uint256).max);

		bytes32[] memory emptyBytes;
		uint256 totalAmountBefore = launchpad.totalPurchasedAmount();

		vm.prank(alice);
		vm.expectRevert(); // TODO: add reason
		launchpad.buyTokens{value: _amount}(emptyBytes);
		
		assertEq(launchpad.purchasedAmount(alice), 0);
		assertEq(launchpad.totalPurchasedAmount(), 0);

		skip(2 days);
		vm.prank(alice);
		launchpad.buyTokens{value: _amount}(emptyBytes);

		assertEq(launchpad.purchasedAmount(alice), launchpad.ethToToken(_amount));
		assertEq(launchpad.totalPurchasedAmount(), totalAmountBefore + launchpad.ethToToken(_amount));

		skip(5 days);
		vm.prank(alice);
		vm.expectRevert();
		launchpad.buyTokens{value: _amount}(emptyBytes);
	}

    function test_transferOwnership() public {
		address alice = makeAddr("alice");
		address bob = makeAddr("bob");
		vm.deal(alice, type(uint256).max);
		bytes32[] memory emptyBytes;

		skip(2 days);
		vm.prank(alice);
		launchpad.buyTokens{value: 20e18}(emptyBytes);
        uint256 aliceBalance = launchpad.purchasedAmount(alice);

        assertNotEq(launchpad.purchasedAmount(alice), 0);
        assertEq(launchpad.purchasedAmount(bob), 0);

        vm.prank(alice);
        vm.expectRevert(ExceedBalance.selector);
        launchpad.transferPurchasedOwnership(aliceBalance + 1, bob);

        vm.prank(alice);
        launchpad.transferPurchasedOwnership(aliceBalance, bob);

        assertEq(launchpad.purchasedAmount(alice), 0);
        assertEq(launchpad.purchasedAmount(bob), aliceBalance);
    }

    function test_cantCreateLpBeforePresaleEnd() public {
		assertEq(launchpad.isStarted(), false);
        skip(2 days);
		assertEq(launchpad.isStarted(), true);

        vm.prank(team);
        vm.expectRevert(PresaleNotEnded.selector);
        launchpad.createLp(0);

        skip(5 days + 1 days + 1); // presale end + release delay + some time
        vm.prank(team);
        vm.expectRevert(ReleaseDelayPassed.selector);
        launchpad.createLp(0);
    }

    function test_terminateLiquidity() public {
        uint256 depositAmount = 10e18;

        skip(2 days);
        address alice = makeAddr("alice");
        vm.deal(alice, type(uint256).max);
        bytes32[] memory emptyBytes;
        vm.prank(alice);
        launchpad.buyTokens{value: depositAmount}(emptyBytes);

        vm.prank(team);
        vm.expectRevert(PresaleNotEnded.selector);
        launchpad.terminateLiquidity();

        skip(5 days); // presale end 
        vm.expectRevert(OnlyOperator.selector);
        launchpad.terminateLiquidity();

        vm.prank(alice);
        vm.expectRevert(LiquidityNotTerminated.selector);
        launchpad.withdrawEth();

        skip(1 days + 1); // presale end + release delay, anyone can terminate
        launchpad.terminateLiquidity();

        assertTrue(launchpad.terminated());

        // claim ETH back
        uint256 aliceBalanceBefore = alice.balance;
        vm.prank(alice);
        launchpad.withdrawEth();
        assertGe(alice.balance, aliceBalanceBefore + depositAmount);

        // claim tokens back
        uint256 teamBalanceBefore = mockToken.balanceOf(team);
        vm.prank(team);
        launchpad.withdrawTokens();
        assertGe(mockToken.balanceOf(team), teamBalanceBefore + launchpad.tokenHardCap());
    }

    function test_cantTerminateLiquidityWhenLpExists() public {
        address alice = makeAddr("alice");
        vm.deal(alice, type(uint256).max);

        skip(2 days);

        // alice buys all tokens
        bytes32[] memory emptyBytes;
        vm.prank(alice);
        launchpad.buyTokens{value: 100e18}(emptyBytes);

        uint ethInAfterFee = ((100e18 * (10_000 - protocolFee)) / 10_000);
        uint tokenIn = ((ethInAfterFee * launchpad.decimals()) / launchpad.ethPricePerToken()) - 10e18;

        skip(5 days); // presale end, only operator can terminate

        vm.startPrank(team);
        launchpad.createLp(tokenIn);

        vm.expectRevert(LPExists.selector);
        launchpad.terminateLiquidity();
    }

    function test_terminateLiquidityOperator() public {
        skip(2 days);

        vm.prank(team);
        vm.expectRevert(PresaleNotEnded.selector);
        launchpad.terminateLiquidity();

        skip(5 days); // presale end 
        vm.expectRevert(OnlyOperator.selector);
        launchpad.terminateLiquidity();
    }

	function test_createLP(uint256 _offset) public {
        vm.assume(_offset >= 1e18 && _offset < 500e18); // the higher the offset, the higher new price will be

        address alice = makeAddr("alice");
        vm.deal(alice, type(uint256).max);

        skip(2 days);

        // alice buys all tokens
        bytes32[] memory emptyBytes;
        vm.prank(alice);
        launchpad.buyTokens{value: 100e18}(emptyBytes);

        vm.prank(alice);
        vm.expectRevert(HardCapOverflow.selector);
        launchpad.buyTokens{value: 1e18}(emptyBytes);


        skip(6 days);

        uint ethInAfterFee = ((100e18 * (10_000 - protocolFee)) / 10_000);
        uint tokenIn = ((ethInAfterFee * launchpad.decimals()) / launchpad.ethPricePerToken()) - _offset;

        vm.prank(team);
        address pool = launchpad.createLp(tokenIn);

        assertFalse(pool == address(0));

        uint newEthpricePerToken = UniswapV2Library.quote(1 ether, tokenIn, ethInAfterFee);
        assertGt(newEthpricePerToken, launchpad.ethPricePerToken());
	}

	function test_factoryReceivesFees(uint256 _buyAmount) public {
        vm.assume(_buyAmount >= 1e18 && _buyAmount <= 100e18);

        address alice = makeAddr("alice");
        vm.deal(alice, type(uint256).max);

        skip(2 days);

        bytes32[] memory emptyBytes;
        vm.prank(alice);
        launchpad.buyTokens{value: _buyAmount}(emptyBytes);

        skip(6 days);

        uint256 factoryBalanceBefore = address(factory).balance;

        uint256 ethInAfterFee = ((_buyAmount * (10_000 - protocolFee)) / 10_000);
        uint256 tokenIn = ((ethInAfterFee * launchpad.decimals()) / launchpad.ethPricePerToken()) - 1e18;

        vm.prank(team);
        launchpad.createLp(tokenIn);

        assertGe(address(factory).balance, factoryBalanceBefore + (_buyAmount - ethInAfterFee));
    }

	function test_linearVestingPeriods() public {
        // Arange
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        vm.deal(alice, type(uint256).max);
        vm.deal(bob, type(uint256).max);

        skip(2 days);

        bytes32[] memory emptyBytes;
        vm.prank(alice);
        launchpad.buyTokens{value: 20e18}(emptyBytes);
        vm.prank(bob);
        launchpad.buyTokens{value: 20e18}(emptyBytes);

        skip(5 days);

        uint256 ethInAfterFee = ((40e18 * (10_000 - protocolFee)) / 10_000);
        uint256 tokenIn = ((ethInAfterFee * launchpad.decimals()) / launchpad.ethPricePerToken()) - 1e18;

        uint256 dailyMax = 57.14e18; // TODO: calculate the value

        vm.prank(team);
        launchpad.createLp(tokenIn);

        // Act, Assert
        vm.startPrank(alice);
        vm.expectRevert(NotClaimable.selector);
        launchpad.claimTokens(1e18);

        skip(1 days);

        vm.expectRevert(AmountZero.selector);
        launchpad.claimTokens(0);

        uint256 purchasedAmountAlice = launchpad.purchasedAmount(alice);
        vm.expectRevert(ExceedClaimableAmount.selector);
        launchpad.claimTokens(purchasedAmountAlice + 1);

        uint256 tokenAmount = 20e18;
        launchpad.claimTokens(tokenAmount);
        vm.stopPrank();
        assertEq(launchpad.totalClaimedAmount(), tokenAmount);

        vm.prank(bob);
        vm.expectRevert(CapForPeriodReached.selector);
        launchpad.claimTokens((dailyMax - tokenAmount) + 1e18);

        skip(1 days);

        vm.prank(bob);
        launchpad.claimTokens((dailyMax * 2) - tokenAmount);

        skip(10 days); // vesting is over

        uint256 bobBefore = mockToken.balanceOf(bob);
        tokenAmount = launchpad.claimableAmount(bob);
        vm.prank(bob);
        launchpad.claimTokens(tokenAmount);
        assertEq(mockToken.balanceOf(bob), bobBefore + tokenAmount);

        uint256 aliceBefore = mockToken.balanceOf(alice);
        tokenAmount = launchpad.claimableAmount(alice);
        vm.prank(alice);
        launchpad.claimTokens(tokenAmount);
        assertEq(mockToken.balanceOf(alice), aliceBefore + tokenAmount);
    }
}
