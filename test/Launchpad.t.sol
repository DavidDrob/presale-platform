pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import "src/Launchpad.sol";

contract LaunchPadTest is Test {
	address factory = makeAddr("factory");
	address team = makeAddr("team");
	address treasury = makeAddr("treasury");
	uint256 protocolFee = 100; // 1% in BP

	ERC20Mock mockToken;
	Launchpad launchpad;

	function setUp() public {
		mockToken = new ERC20Mock();
		mockToken.mint(team, 100_000e18);

		// skip, so block.timestamp doesn't underflow in some tests
		skip(11 days);

		MainLaunchpadInfo memory info = MainLaunchpadInfo({
			name: "Sample Presale",
			token: IERC20(address(mockToken)),
			ethPricePerToken: 0.1 ether,
			decimals: 1 ether,
			tokenHardCap: 1000 ether,
			minTokenBuy: 0,
			maxTokenBuy: type(uint256).max,

			startDate: block.timestamp + 2 days,
			endDate: block.timestamp + 7 days,
			releaseDelay: 1 days,
			vestingDuration: 7 days
		});

		// TODO: use CREATE2 to get a predeterministic address to prevent an extra call
		vm.startPrank(team);
		launchpad = new Launchpad(info, protocolFee, treasury, team, factory);
		mockToken.approve(address(launchpad), type(uint256).max);
		launchpad.initialize();
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
		vm.assume(_newDate > block.timestamp - 10 days);
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
				  && _amount >= launchpad.minTokenBuy()
				  && _amount <= launchpad.tokenHardCap() - launchpad.totalPurchasedAmount()
		);

		address alice = makeAddr("alice");
		vm.deal(alice, type(uint256).max);

		bytes32[] memory emptyBytes;
		uint256 totalAmountBefore = launchpad.totalPurchasedAmount();

		vm.prank(alice);
		vm.expectRevert();
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
}
