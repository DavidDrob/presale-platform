pragma solidity ^0.8.20;

// init
error InvalidEthPrice();
error InvalidMinTokenBuy();
error InvalidMaxTokenBuy();
error InvalidStartDate();
error InvalidEndDate();
error ZeroAddress();

// presale
error PresaleAlreadyStarted();
error PresaleEnded();
error PresaleNotStarted();
error PresaleNotEnded();
error AmountTooLow();
error AmountTooHigh();
error NotWhitelisted();

// pre-liquidity phase
error ReleaseDelayPassed();
error LPExists();
error LiquidityNotTerminated();

// liquidity phase
error NotClaimable();
error ExceedClaimableAmount();
error CapForPeriodReached();
error ClaimingAlreadyStarted();

// other
error AmountZero();
error InvalidReleaseDelay();
error PriceTooLow();
error OnlyOperator();
error HardCapOverflow();
error TransferFailed();
error ExceedBalance();
