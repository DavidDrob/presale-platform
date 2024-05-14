pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/mocks/MockERC20.sol";

import "src/Launchpad.sol";

contract LaunchPadTest is Test {
	address factory = makeAddr("factory");
	address team = makeAddr("team");
	address treasury = makeAddr("treasury");
	uint256 protocolFee = 100; // 1% in BP

	Launchpad launchpad;

	function setUp() public {
		MockERC20 mockToken = new MockERC20();
		mockToken.initialize("Sample Token", "STKN", 18);

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

		launchpad = new Launchpad(info, protocolFee, treasury, team, factory);
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
}
