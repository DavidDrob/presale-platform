pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import "src/Factory.sol";
import "src/Launchpad.sol";
import "./utils/SampleData.sol";

contract LaunchpadFactoryTest is Test {
	address team = makeAddr("team");
	address treasury = makeAddr("treasury");
	uint256 protocolFee = 1000; // 10% in BP
    address alice = makeAddr("alice");
	ERC20Mock mockToken;
    LaunchpadFactory factory;

	function setUp() public {
        factory = new LaunchpadFactory(protocolFee, treasury);

		mockToken = new ERC20Mock();
		mockToken.mint(team, 100_000e18);
    }

    function test_deployLaunchpad() public {
        MainLaunchpadInfo memory info = SampleData._getSampleInfo(address(mockToken));

        vm.prank(alice);
        Launchpad launchpad = Launchpad(factory.createLaunchpad(info));

        assertEq(launchpad.operator(), alice);
        assertEq(launchpad.name(), info.name);
    }
}
