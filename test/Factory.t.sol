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
    ERC20Mock mockToken;
    LaunchpadFactory factory;

    function setUp() public {
        factory = new LaunchpadFactory(protocolFee, treasury);

        mockToken = new ERC20Mock();
        mockToken.mint(team, 100_000e18);
    }

    function test_deployLaunchpad() public {
        // calculate address via CREATE2
        MainLaunchpadInfo memory info = SampleData._getSampleInfo(address(mockToken));
        bytes32 salt = factory.calculateSalt(team, info.name, address(info.token));
        address launchPadAddress =
            factory.getLaunchpadAddress(salt, info, protocolFee, treasury, team, address(factory));

        vm.startPrank(team);
        mockToken.approve(launchPadAddress, info.tokenHardCap);
        Launchpad launchpad = Launchpad(factory.createLaunchpad(info, salt));
        vm.stopPrank();

        assertEq(launchpad.operator(), team);
        assertEq(launchpad.name(), info.name);
        assertEq(launchPadAddress, address(launchpad));

        uint256 launchpadBalance = info.token.balanceOf(address(launchpad));
        assertEq(launchpadBalance, info.tokenHardCap);
    }
}
