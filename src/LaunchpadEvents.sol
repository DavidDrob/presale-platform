pragma solidity ^0.8.20;

library LaunchpadEvents {
    // Events
    event TokensPurchased(address indexed _token, address indexed buyer, uint256 amount);
    event TokensClaimed(address indexed _token, address indexed buyer, uint256 amount);
    event EthPricePerTokenUpdated(address indexed _token, uint256 newEthPricePerToken);
    event WhitelistUpdated(uint256 wlBlockNumber, uint256 wlMinBalance, bytes32 wlRoot);
    event TokenHardCapUpdated(address indexed _token, uint256 newTokenHardCap);
    event OperatorTransferred(address indexed previousOperator, address indexed newOperator);
    event VestingDurationUpdated(uint256 newVestingDuration);
}
