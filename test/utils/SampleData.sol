pragma solidity ^0.8.20;

import "src/Factory.sol";
import "src/Launchpad.sol";

library SampleData {
    function _getSampleInfo(address _mockToken) internal view returns (MainLaunchpadInfo memory) {
        MainLaunchpadInfo memory info = MainLaunchpadInfo({
            name: "Sample Presale",
            token: IERC20(address(_mockToken)),
            ethPricePerToken: 0.1 ether,
            decimals: 1 ether,
            tokenHardCap: 1000 ether,
            minTokenBuy: 1e18,
            maxTokenBuy: type(uint256).max,
            startDate: block.timestamp + 2 days,
            endDate: block.timestamp + 7 days,
            releaseDelay: 1 days,
            vestingDuration: 7 days
        });

        return info;
    }
}
