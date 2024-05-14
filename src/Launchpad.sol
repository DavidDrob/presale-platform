pragma solidity ^0.8.20;

import "forge-std/interfaces/IERC20.sol";

struct MainLaunchpadInfo {
    string name;
    IERC20 token;

    uint256 startDate;
    uint256 endDate;
    uint256 releaseDelay;
    uint256 vestingDuration;
}


contract Launchpad {
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
        _;
    }

    // use OZ implementation
    modifier nonReentrant() {
        _;
    } 

    // Variables
    address public operator;
    string public name;
    IERC20 public immutable token;
    uint256 public immutable decimals; // decimals are already stored in `token`
    uint256 public immutable tokenUnit;
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

    //  Constructor
    constructor(MainLaunchpadInfo memory _info, uint256 _protocolFee, address
    _protocolFeeAddress, address _operator, address _factory) {
        name = _info.name;
        token = _info.token;

        startDate = _info.startDate;
        endDate = _info.endDate;
        releaseDelay = _info.releaseDelay; // e.g. 1 days (86400)
        vestingDuration = _info.vestingDuration; 
        // if vestingDuration was before releaseDay + endDate
        // it could cause problems calculating the claimAmount during vesting later
        require(vestingDuration >= releaseDelay + endDate); 

        // assign remaining values from _info to local variables
        // ...

        protocolFeeAddress = _protocolFeeAddress;
        operator = _operator;
        // ...
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
        return block.timestamp >= endDate + releaseDelay;
    }

    // *** ONLY OPERATOR SETTERS *** //
    // only authorized actors should be able to modify these parameters so we use `onlyOperator`

    function transferOperatorOwnership(address newOperator) external onlyOperator {
	    operator = newOperator;
    }

    // only allow updating startDate before the pre-sale starts
    function updateStartDate(uint _newStartDate) external onlyOperator {}

    // only allow updating endDate before the vesting starts
    // otherwise tokens could be claimed before the pre-sale ends
    function updateEndDate(uint _newEndDate) external onlyOperator {}


    function updateWhitelist(uint256 _wlBlockNumber, uint256 _wlMinBalance,
    bytes32 _wlRoot) external onlyOperator {
	    wlBlockNumber = _wlBlockNumber;
	    wlMinBalance = _wlMinBalance;
	    wlRoot = _wlRoot;
    }

    function increaseHardCap(uint256 _tokenHardCapIncrement) external onlyOperator {
	// use unchecked only if we assume the operator knows what they're doing.
    // unchecked saves gas
	// unchecked {
        tokenHardCap += _tokenHardCapIncrement;
	// }
    }

    // only allow updating vestingDuration before the vesting starts
    // otherwise it could mess up the calculation of the claimable amounts in a vesting timeframe
    function setVestingDuration(uint256 _vestingDuration) external onlyOperator {
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
    // *** ONLY OPERATOR SETTERS *** //


    // ethPricePerToken and ethAmount both have 18 decimals
    // take decimals into account when using something other then ETH in the future.
    // 
    // this function should be public as it's also used internally.
    function ethToToken(uint256 ethAmount) public view returns (uint256) {
        return (ethAmount - protocolFee) / ethPricePerToken;
    }

    // use `nonReentrant` so the user can't abuse msg.value to purchase more then they deposit
    function buyTokens(bytes32[] calldata proof) external payable nonReentrant {
        uint256 tokenAmount = ethToToken(msg.value); // protocol fee is accounted in `ethToToken` already

    	// ensure the amount doesn't overflow the hardcap
        require(totalPurchasedAmount + tokenAmount < tokenHardCap);

    	// ensure amount is in allowed range 
        require(minTokenBuy < tokenAmount &&
                tokenAmount <= maxTokenBuy);


        // update `purchasedAmount` and `totalPurchasedAmount`
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