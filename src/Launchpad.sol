pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import "./Errors.sol";

import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IUniswapV2Factory.sol";

struct MainLaunchpadInfo {
    string name;
    IERC20 token;
    uint256 ethPricePerToken;
    uint256 decimals;
    uint256 tokenHardCap;
    uint256 minTokenBuy;
    uint256 maxTokenBuy;
    uint256 startDate;
    uint256 endDate;
    uint256 releaseDelay;
    uint256 vestingDuration;
}

contract Launchpad is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Events
    event TokensPurchased(address indexed _token, address indexed buyer, uint256 amount);
    event TokensClaimed(address indexed _token, address indexed buyer, uint256 amount);
    event EthPricePerTokenUpdated(address indexed _token, uint256 newEthPricePerToken);
    event WhitelistUpdated(bytes32 wlRoot);
    event TokenHardCapUpdated(address indexed _token, uint256 newTokenHardCap);
    event OperatorTransferred(address indexed previousOperator, address indexed newOperator);
    event VestingDurationUpdated(uint256 newVestingDuration);

    // Modifiers
    modifier onlyOperator() {
        if (msg.sender != operator) revert OnlyOperator();

        _;
    }

    // constants
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    IUniswapV2Factory constant uniswapFactory = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    IUniswapV2Router02 constant uniswapRouter = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    // Variables
    address public immutable factory;
    address public operator;

    string public name;
    IERC20 public immutable token;
    uint256 public immutable decimals; // decimals of native token

    uint256 public ethPricePerToken;
    uint256 public tokenHardCap;
    uint256 public minTokenBuy;
    uint256 public maxTokenBuy;
    bytes32 public wlRoot;

    uint256 public startDate;
    uint256 public endDate;
    uint256 public releaseDelay; // time between pre-sale end and vesting start, and vesting timeframes
    uint256 public vestingDuration;

    uint256 public protocolFee;
    address public protocolFeeAddress;

    mapping(address => uint256) public purchasedAmount;
    mapping(address => uint256) public claimedAmount;
    uint256 public totalPurchasedAmount;
    uint256 public totalClaimedAmount;

    bool public terminated;
    address public liquidityPoolAddress;
    uint256 public releasePerDay;

    //  Constructor
    constructor(
        MainLaunchpadInfo memory _info,
        uint256 _protocolFee,
        address _protocolFeeAddress,
        address _operator,
        address _factory
    ) {
        if (_info.releaseDelay == 0) revert InvalidReleaseDelay();
        if (_info.ethPricePerToken == 0) revert InvalidEthPrice();
        if (_info.minTokenBuy == 0) revert InvalidMinTokenBuy();
        if (_info.maxTokenBuy == 0) revert InvalidMaxTokenBuy();
        if (_info.startDate <= block.timestamp) revert InvalidStartDate();
        if (_info.endDate <= _info.startDate) revert InvalidEndDate();
        if (_operator == address(0)) revert ZeroAddress();

        factory = _factory;
        operator = _operator;

        name = _info.name;
        token = _info.token;
        decimals = _info.decimals;

        ethPricePerToken = _info.ethPricePerToken;
        tokenHardCap = _info.tokenHardCap;
        minTokenBuy = _info.minTokenBuy;
        maxTokenBuy = _info.maxTokenBuy;

        startDate = _info.startDate;
        endDate = _info.endDate;
        releaseDelay = _info.releaseDelay; // e.g. 1 days (86400)
        vestingDuration = _info.vestingDuration;

        protocolFee = _protocolFee;
        protocolFeeAddress = _protocolFeeAddress;

        token.safeTransferFrom(operator, address(this), tokenHardCap);
        assert(token.balanceOf(address(this)) >= tokenHardCap);
    }

    // Contract functions

    // *** VIEW FUNCTIONS *** //
    // these functions will also be used internally, so we make them public
    //
    // the gas aspect of using public vs external is irrelevant
    // because there are no arguments
    function isStarted() public view returns (bool) {
        return block.timestamp >= startDate;
    }

    function isEnded() public view returns (bool) {
        return block.timestamp >= endDate;
    }

    function isClaimable() public view returns (bool) {
        return (block.timestamp >= endDate + releaseDelay && !terminated);
    }

    function availableNow() public view returns (uint256) {
        uint256 daysSinceVestingStart = ((block.timestamp - (endDate + releaseDelay)) / 1 days) + 1; // rounds down automatically
        return ((releasePerDay * daysSinceVestingStart) - totalClaimedAmount);
    }

    function claimableAmount(address _address) public view returns (uint256) {
        return purchasedAmount[_address] - claimedAmount[_address];
    }

    function claimableAmountNow(address _address) public view returns (uint256) {
        uint256 claimableUser = claimableAmount(_address);
        uint256 availableTokens = availableNow();

        if (claimableUser >= availableTokens) {
            return availableTokens;
        } else {
            return claimableUser;
        }
    }

    // ethPricePerToken and ethAmount both have 18 decimals
    // take decimals into account when using something other then ETH in the future.
    //
    // this function should be public as it's also used internally.
    function ethToToken(uint256 ethAmount) public view returns (uint256) {
        return (ethAmount * decimals) / ethPricePerToken;
    }

    function tokenToEth(uint256 tokenAmount) public view returns (uint256) {
        return (tokenAmount * ethPricePerToken) / decimals;
    }

    // *** ONLY OPERATOR SETTERS *** //
    // only authorized actors should be able to modify these parameters so we use `onlyOperator`

    function transferOperatorOwnership(address newOperator) external onlyOperator {
        address previousOperator = operator;
        operator = newOperator;

        emit OperatorTransferred(previousOperator, newOperator);
    }

    // only allow updating startDate before the pre-sale starts
    function updateStartDate(uint256 _newStartDate) external onlyOperator {
        if (isStarted()) revert PresaleAlreadyStarted();
        if (_newStartDate >= endDate) revert InvalidEndDate();

        startDate = _newStartDate;
    }

    // only allow updating endDate before the vesting starts
    // otherwise tokens could be claimed before the pre-sale ends
    function updateEndDate(uint256 _newEndDate) external onlyOperator {
        if (isClaimable()) revert InvalidEndDate();
        if (_newEndDate <= startDate) revert InvalidEndDate();

        endDate = _newEndDate;
    }

    function updateWhitelist(bytes32 _wlRoot) external onlyOperator {
        wlRoot = _wlRoot;

        emit WhitelistUpdated(_wlRoot);
    }

    function increaseHardCap(uint256 _tokenHardCapIncrement) external onlyOperator {
        token.safeTransferFrom(msg.sender, address(this), _tokenHardCapIncrement);

        // use unchecked only if we assume the operator knows what they're doing.
        // unchecked saves gas
        unchecked {
            tokenHardCap += _tokenHardCapIncrement;
        }

        emit TokenHardCapUpdated(address(token), tokenHardCap);
    }

    // only allow updating vestingDuration before the vesting starts
    // otherwise it could mess up the calculation of the claimable amounts in a vesting timeframe
    function setVestingDuration(uint256 _vestingDuration) external onlyOperator {
        if (isClaimable()) revert ClaimingAlreadyStarted();

        vestingDuration = _vestingDuration;

        emit VestingDurationUpdated(_vestingDuration);
    }

    function updateEthPricePerToken(uint256 _ethPricePerToken) external onlyOperator {
        if (isStarted()) revert PresaleAlreadyStarted();

        ethPricePerToken = _ethPricePerToken;

        emit EthPricePerTokenUpdated(address(token), _ethPricePerToken);
    }

    function setName(string memory _name) external onlyOperator {
        name = _name;
    }

    function createLp(uint256 tokenIn) external onlyOperator returns (address) {
        if (!isEnded()) revert PresaleNotEnded();
        if (block.timestamp > endDate + releaseDelay) revert ReleaseDelayPassed();

        address pool = uniswapFactory.createPair(WETH, address(token));

        // prevent donation attack by not using `address(this).balance`
        uint256 ethIn = (totalPurchasedAmount * ethPricePerToken) / decimals;
        uint256 ethInAfterFee = ((ethIn * (10_000 - protocolFee)) / 10_000);
        if (tokenIn >= ((ethInAfterFee * decimals) / ethPricePerToken)) revert PriceTooLow();

        token.safeTransferFrom(operator, address(this), tokenIn);
        token.approve(address(uniswapRouter), tokenIn);

        // TODO: add slippage
        uniswapRouter.addLiquidityETH{value: ethInAfterFee}(address(token), tokenIn, 0, 0, operator, block.timestamp);

        liquidityPoolAddress = pool;
        releasePerDay = (totalPurchasedAmount / (vestingDuration / 1 days));

        (bool sent,) = (factory).call{value: (ethIn - ethInAfterFee)}("");
        assert(sent);

        return pool;
    }

    // operator can terminate liquidity before releaseDelay
    // anyone can terminate liquidity after releaseDelay (project was abandoned by operator)
    // reverts before presale end or if LP has already been created
    function terminateLiquidity() external {
        if (!isEnded()) revert PresaleNotEnded();
        if (liquidityPoolAddress != address(0)) revert LPExists();

        if (block.timestamp > endDate + releaseDelay || msg.sender == operator) {
            terminated = true;
        } else {
            revert OnlyOperator();
        }
    }

    // NOTE: make proof optional, by making `buyTokens` internal and adding
    // one more external function without the proof parameter
    //
    // use `nonReentrant` so the user can't abuse msg.value to purchase more then they deposit
    function buyTokens(bytes32[] calldata proof) external payable nonReentrant {
        if (!isStarted()) revert PresaleNotStarted();
        if (isEnded()) revert PresaleEnded();

        if (wlRoot != bytes32(0) && !MerkleProof.verifyCalldata(proof, wlRoot, keccak256((abi.encode(msg.sender))))) {
            revert NotWhitelisted();
        }

        uint256 tokenAmount = ethToToken(msg.value);

        // ensure the amount doesn't overflow the hardcap
        if (totalPurchasedAmount + tokenAmount > tokenHardCap) revert HardCapOverflow();

        // ensure amount is in allowed range
        if (tokenAmount < minTokenBuy) revert AmountTooLow();
        if (tokenAmount > maxTokenBuy) revert AmountTooHigh();

        // update `purchasedAmount` and `totalPurchasedAmount`
        purchasedAmount[msg.sender] = tokenAmount;
        totalPurchasedAmount += tokenAmount;

        emit TokensPurchased(address(token), msg.sender, tokenAmount);
    }

    // IDEA: figure out how to calculate an amount so that
    // one user doesn't claim all available tokens for a vesting timeframe at once
    // not sure if this is necessary though
    function claimTokens(uint256 _amount) external {
        if (!isClaimable()) revert NotClaimable();
        if (_amount == 0) revert AmountZero();
        if (_amount > claimableAmount(msg.sender)) revert ExceedClaimableAmount();

        uint256 availableTokens = availableNow();

        if (_amount > availableTokens) revert CapForPeriodReached();

        claimedAmount[msg.sender] += _amount;
        totalClaimedAmount += _amount;

        token.safeTransfer(msg.sender, _amount);

        emit TokensClaimed(address(token), msg.sender, _amount);
    }

    // return ETH to users if the operator chooses not to continue vesting
    // not sure if `nonReentrant` is necessary, but keep it for now
    function withdrawEth() external nonReentrant {
        if (!terminated) revert LiquidityNotTerminated();

        uint256 transferAmount = tokenToEth(purchasedAmount[msg.sender]);
        purchasedAmount[msg.sender] = 0;

        (bool sent,) = (msg.sender).call{value: transferAmount}("");
        if (!sent) revert TransferFailed();
    }

    // return tokens if the operator chooses not to continue vesting
    function withdrawTokens() external onlyOperator {
        if (!terminated) revert LiquidityNotTerminated();

        token.safeTransfer(operator, tokenHardCap);
    }

    function transferPurchasedOwnership(uint256 _amount, address _newOwner) external {
        if (_amount == 0) revert AmountZero();
        if (_amount > purchasedAmount[msg.sender]) revert ExceedBalance();
        if (_amount + purchasedAmount[_newOwner] > maxTokenBuy) revert AmountTooHigh();

        purchasedAmount[msg.sender] -= _amount;
        purchasedAmount[_newOwner] += _amount;
    }
}
