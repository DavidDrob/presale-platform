pragma solidity ^0.8.20;

// presale
error PresaleAlreadyStarted();
error PresaleEnded();
error PresaleNotStarted();
error PresaleNotEnded();
error AmountTooLow();
error AmountTooHigh();

// pre-liquidity phase
error ReleaseDelayPassed();
error LPExists();
error LiquidityNotTerminated();

// liquidity phase
error NotClaimable();
error ExceedClaimableAmount();
error CapForPeriodReached();

// other
error AmountZero();
error InvalidEndDate();
error InvalidVestingDuration();
error PriceTooLow();
error OnlyOperator();
error HardCapOverflow();
error TransferFailed();
