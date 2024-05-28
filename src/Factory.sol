pragma solidity ^0.8.20;

import "./Launchpad.sol";

contract LaunchpadFactory {
    uint256 public immutable protocolFee;
    address public immutable treasury;

    constructor(uint256 _protocolFee, address _treasury) {
        protocolFee = _protocolFee;
        treasury = _treasury;
    }

    function createLaunchpad(MainLaunchpadInfo memory _info, bytes32 _salt) external returns (address launchpad) {
        return address(new Launchpad{salt: _salt}(_info, protocolFee, treasury, msg.sender, address(this)));
    }

    function getLaunchpadAddress(
        bytes32 salt,
        MainLaunchpadInfo memory _info,
        uint256 _protocolFee,
        address _protocolFeeAddress,
        address _operator,
        address _factory
    ) public view returns (address) {
        bytes memory params = abi.encode(_info, _protocolFee, _protocolFeeAddress, _operator, _factory);

        bytes memory code = abi.encodePacked(type(Launchpad).creationCode, params);
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(code)));
        return address(uint160(uint256(hash)));
    }

    function calculateSalt(address operator, string memory name, address token) external pure returns (bytes32) {
        return keccak256(abi.encode(operator, name, token));
    }

    receive() external payable {}
}
