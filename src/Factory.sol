pragma solidity ^0.8.20;

import "./Launchpad.sol";

contract LaunchpadFactory {
    uint256 public immutable protocolFee;
    address public immutable treasury;

    constructor(uint256 _protocolFee, address _treasury) {
        protocolFee = _protocolFee;
        treasury = _treasury;
    }

    function createLaunchpad(MainLaunchpadInfo memory _info) external returns (address launchpad) {
        return address(new Launchpad(_info, protocolFee, treasury, msg.sender, address(this)));
    }
}
