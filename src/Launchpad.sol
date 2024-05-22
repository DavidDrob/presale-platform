pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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


contract Launchpad {
    using SafeERC20 for IERC20;

    // Events
    event TokensPurchased(address indexed _token, address indexed buyer, uint256
    amount);
    event TokensClaimed(address indexed _token, address indexed buyer, uint256
    amount);
    event EthPricePerTokenUpdated(address indexed _token, uint256
    newEthPricePerToken);
    event WhitelistUpdated(uint256 wlBlockNumber, uint256 wlMinBalance, bytes32
    wlRoot);
    event TokenHardCapUpdated(address indexed _token, uint256 newTokenHardCap);
    event OperatorTransferred(address indexed previousOperator, address indexed
    newOperator);
    event VestingDurationUpdated(uint256 newVestingDuration);

    // Modifiers
    modifier onlyOperator() {
        require(msg.sender == operator);

        _;
    }

    // use OZ implementation
    modifier nonReentrant() {
        _;
    } 

    // constants
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // Variables
    address public operator;
    string public name;
    IERC20 public immutable token;
    uint256 public immutable decimals; // decimals of native token
    // uint256 public immutable tokenUnit; // decimals are already stored in `token`
    address public immutable factory;
    uint256 public ethPricePerToken;
    uint256 public tokenHardCap;
    uint256 public minTokenBuy;
    uint256 public maxTokenBuy;
    uint256 public startDate;
    uint256 public endDate;
    uint256 public protocolFee;
    address public protocolFeeAddress;
    uint256 public releaseDelay; // time between pre-sale end and vesting start, and vesting timeframes
    uint256 public vestingDuration;
    mapping(address => uint256) public purchasedAmount;
    mapping(address => uint256) public claimedAmount;
    uint256 public totalPurchasedAmount;
    uint256 public wlBlockNumber;
    uint256 public wlMinBalance;
    bytes32 public wlRoot;

    IUniswapV2Factory uniswapFactory = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    IUniswapV2Router02 uniswapRouter = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    //  Constructor
    constructor(MainLaunchpadInfo memory _info, uint256 _protocolFee, address
    _protocolFeeAddress, address _operator, address _factory) {
        name = _info.name;
        token = _info.token;
        ethPricePerToken = _info.ethPricePerToken;
        decimals = _info.decimals;
        tokenHardCap = _info.tokenHardCap;
        minTokenBuy = _info.minTokenBuy;
        maxTokenBuy = _info.maxTokenBuy;

        startDate = _info.startDate;
        endDate = _info.endDate;
        releaseDelay = _info.releaseDelay; // e.g. 1 days (86400)
        vestingDuration = _info.vestingDuration; 

        // if releaseDelay was after vestingDuration
        // it could cause problems calculating the claimAmount during vesting later
        require(vestingDuration >= releaseDelay, "Vesting starts after releaseDelay"); 

        protocolFee = _protocolFee;
        protocolFeeAddress = _protocolFeeAddress;
        operator = _operator;
        factory = _factory;

        token.safeTransferFrom(operator, address(this), tokenHardCap);
        assert(token.balanceOf(address(this)) >= tokenHardCap);
    }

    // Contract functions


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
        return false;
        // TODO: check if operator provided liquidity
        return block.timestamp >= endDate + releaseDelay;
    }

    // *** ONLY OPERATOR SETTERS *** //
    // only authorized actors should be able to modify these parameters so we use `onlyOperator`

    function transferOperatorOwnership(address newOperator) external onlyOperator {
	    operator = newOperator;
    }

    // only allow updating startDate before the pre-sale starts
    function updateStartDate(uint _newStartDate) external onlyOperator {
        require(!isStarted(), "Cannot change start date when the pre-sale already started");
        require(_newStartDate < endDate, "Cannot start before the end");

        startDate = _newStartDate;
    }

    // only allow updating endDate before the vesting starts
    // otherwise tokens could be claimed before the pre-sale ends
    function updateEndDate(uint _newEndDate) external onlyOperator {
        require(!isClaimable(), "Cannot change end date after vesting started");
        require(startDate < _newEndDate, "Cannot end before the start");

        endDate = _newEndDate;
    }


    function updateWhitelist(uint256 _wlBlockNumber, uint256 _wlMinBalance,
    bytes32 _wlRoot) external onlyOperator {
	    wlBlockNumber = _wlBlockNumber;
	    wlMinBalance = _wlMinBalance;
	    wlRoot = _wlRoot;
    }

    function increaseHardCap(uint256 _tokenHardCapIncrement) external onlyOperator {
        token.safeTransferFrom(msg.sender, address(this), _tokenHardCapIncrement);

        // use unchecked only if we assume the operator knows what they're doing.
        // unchecked saves gas
        unchecked {
            tokenHardCap += _tokenHardCapIncrement;
        }
    }

    // only allow updating vestingDuration before the vesting starts
    // otherwise it could mess up the calculation of the claimable amounts in a vesting timeframe
    function setVestingDuration(uint256 _vestingDuration) external onlyOperator {
        require(!isClaimable(), "Cannot change vesting duration after vesting started");

        vestingDuration = _vestingDuration;
    }

    function updateEthPricePerToken(uint256 _ethPricePerToken) external onlyOperator {
        // consider allowing this only before the presale starts for now
        // as it could complicate calculating the ratio of token/ETH for the LP
        ethPricePerToken = _ethPricePerToken;
    }

    function setName(string memory _name) external onlyOperator {
        name = _name;
    }

    function createLp(uint tokenIn) external onlyOperator returns (address) {
        require(isEnded(), "presale didn't end yet");

        address pool = uniswapFactory.createPair(WETH, address(token));

        // prevent donation attack by not using `address(this).balance`
        uint ethIn = (totalPurchasedAmount * ethPricePerToken) / decimals; 
        uint ethInAfterFee = ((ethIn * (10_000 - protocolFee)) / 10_000);
        require(tokenIn < ((ethInAfterFee * decimals) / ethPricePerToken), "price is below ethPricePerToken");

        token.safeTransferFrom(operator, address(this), tokenIn);
        token.approve(address(uniswapRouter), tokenIn);

        // TODO: add slippage
        uniswapRouter.addLiquidityETH{value: ethIn}(address(token), tokenIn, 0, 0, operator, block.timestamp);

        return pool;
    }
    // *** ONLY OPERATOR SETTERS *** //


    // ethPricePerToken and ethAmount both have 18 decimals
    // take decimals into account when using something other then ETH in the future.
    // 
    // this function should be public as it's also used internally.
    function ethToToken(uint256 ethAmount) public view returns (uint256) {
        // TODO: add fee calculation
        return (ethAmount * decimals) / ethPricePerToken;
    }

    // NOTE: make proof optional, by making `buyTokens` internal and adding
    // one more external function without the proof parameter
    //
    // use `nonReentrant` so the user can't abuse msg.value to purchase more then they deposit
    function buyTokens(bytes32[] calldata proof) external payable nonReentrant {
        require(isStarted(), "presale not started");
        require(!isEnded(), "presale ended");

        uint256 tokenAmount = ethToToken(msg.value); // protocol fee is accounted in `ethToToken` already

    	// ensure the amount doesn't overflow the hardcap
        require(totalPurchasedAmount + tokenAmount <= tokenHardCap, "hardcap overflow");

    	// ensure amount is in allowed range 
        require(minTokenBuy <= tokenAmount &&
                tokenAmount <= maxTokenBuy);

        // update `purchasedAmount` and `totalPurchasedAmount`
        purchasedAmount[msg.sender] = tokenAmount;
        totalPurchasedAmount += tokenAmount;
    }

    function claimableAmount(address _address) external view returns (uint256) {
        // TODO: calculate max amount for the current vesting timeframe
        // return Math.min(maxAmount, purchaseAmount-claimedAmount);

        return purchasedAmount[_address] - claimedAmount[_address];
    }

    function claimTokens() external {
        require(isClaimable());
        
        // IDEA: figure out how to calculate an amount so that
        // one user doesn't claim all available tokens for a vesting timeframe at once 
        // not sure if this is necessary though

        // use safeTranfer because the token could be "weird" (ERC777, missing return on transfer, ...)
        // https://github.com/d-xo/weird-erc20
    }

    
    // return ETH to users if the operator chooses not to continue vesting
    // not sure if `nonReentrant` is necessary, but keep it for now
    function withdrawEth() external nonReentrant {
        require(isEnded());

        // transfer purchasedAmount[msg.sender]

        // update purchasedAmount[msg.sender]
    }

    // return tokens if the operator chooses not to continue vesting
    function withdrawTokens() external onlyOperator {
        require(isEnded());
    }

    function transferPurchasedOwnership(address _newOwner) external {
        address x = _newOwner; // for compiler, implement later
    }
}
