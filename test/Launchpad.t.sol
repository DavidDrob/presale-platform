pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "src/Launchpad.sol";

contract LaunchPadTest is Test {
	function setUp() public {
		MainLaunchpadInfo memory info = MainLaunchpadInfo({
			name: "SampleToken",
			token: IERC20(address(0)),

			startDate: block.timestamp + 2 days,
			endDate: block.timestamp + 7 days,
			releaseDelay: 1 days,
			vestingDuration: 7 days
		});

		new Launchpad(info, 0, address(0), address(0), address(0));
	}
}
