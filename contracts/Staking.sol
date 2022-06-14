// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

// external import
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

// internal import
import "./interfaces/IStaking.sol";
import "./interfaces/IRouter.sol";
import "./admin/RewardsAdministrator.sol";

contract TestStaking is IStaking, RewardsAdministrator, ReentrancyGuard, Pausable {
    event OpenCampaign(uint256 periodStart, uint256 periodFinish, uint256 rewardAmount);
    event Staked(address indexed user, uint256 amount);
    event Unstake(address indexed user, uint256 amount);
    event ClaimReward(address indexed user, uint256 reward);
    event UpdateUnstakeDuration(uint256 newDuration);

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct User {
        uint256 balance;
        uint256 rewardPerTokenPaid;
        uint256 rewards;
        uint256 stakingTime;
    }

    mapping(address => User) private _users;

    uint256 public constant SECONDS_PER_YEAR = 31536000; // ((24 x 60 x 60) x 365)
    uint256 public constant MIN_STAKE_DAYS = 7;
    uint256 public constant PERCENT_DECIMALS = 6;
    address public constant ROUTER_ADDRESS = 0x10ED43C718714eb63d5aA57B78B54704E256024E;

    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardsToken;
    address public immutable tokenOut;
    
    uint256 public periodStart = 0;
    uint256 public periodFinish = 0;
    uint256 public rewardAmount = 0;
    uint256 public rewardRate = 0;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenGlobal;
    address public feeBeneficiary;
    
    uint256 private _totalStakes;

    constructor(
        address _stakingToken,
        address _rewardsToken,
        address _rewardsAdministrator,
        address _rewardsTreasury,
        address _tokenOut
    ) {
        stakingToken = IERC20(_stakingToken);
        rewardsToken = IERC20(_rewardsToken);
        rewardsAdministrator = _rewardsAdministrator;
        rewardsTreasury = _rewardsTreasury;      
        tokenOut = _tokenOut;
        feeBeneficiary = _msgSender();
    }

    modifier updateReward(address account) {
        rewardPerTokenGlobal = rewardPerToken();
        lastUpdateTime = lastUpdated();
        if (account != address(0)) {
            _users[account].rewards = earned(account);
            _users[account].rewardPerTokenPaid = rewardPerTokenGlobal;
        }
        _;
    }

    function rewardPerToken() public view override returns (uint256) {
        if (_totalStakes == 0 || periodStart == 0) return rewardPerTokenGlobal;
        uint256 sTime = lastUpdateTime < periodStart ? periodStart : lastUpdateTime;
        uint256 eTime = lastUpdated();
        if (eTime < sTime) return rewardPerTokenGlobal;
        return 
            rewardPerTokenGlobal
            .add(eTime.sub(sTime).mul(rewardRate).mul(1e18).div(_totalStakes));
    }

    function totalStakes() external view override returns (uint256) {
        return _totalStakes;
    }

    function getApr() public view returns (uint256) {
        if (periodFinish < block.timestamp) return 0;
        return _getApr(rewardRate);
    }

    function estimateApr(uint256 moreRewards, uint256 finishTime) public view returns (uint256) {
        uint256 period = finishTime.sub(block.timestamp);
        uint256 rate = getRemainingReward().add(moreRewards).div(period);

        return _getApr(rate);
    }

    function _getApr(uint256 rate) internal view returns(uint256) {
        if (_totalStakes == 0) return 0;
        return rate.mul(SECONDS_PER_YEAR).mul(100 * (10 ** PERCENT_DECIMALS)).div(_totalStakes);
    }

    function getRemainingReward() public view returns(uint256) {
        if (periodFinish == 0 || periodFinish <= block.number) return 0; // not added rewards yet, or already finished
        uint256 remaining = periodFinish.sub(block.timestamp);
        uint256 leftover = remaining.mul(rewardRate);
        return leftover;
    }

    function getStakingTokenPrice() public view returns(uint256) {
        address[] memory path = new address[](2);
        path[0] = address(stakingToken);
        path[1] = tokenOut;
        return IRouter(ROUTER_ADDRESS).getAmountsOut(1e18, path)[1];
    }

    function getUserInfo(address account) external view override returns (uint256, uint256, uint256, uint256) {
        return (
            _users[account].balance,
            _users[account].rewardPerTokenPaid,
            _users[account].rewards,
            _users[account].stakingTime
        );
    }

    function lastUpdated() public view override returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    function earned(address account) public view override returns (uint256) {
        return 
            _users[account].balance
            .mul(rewardPerToken().sub(_users[account].rewardPerTokenPaid))
            .div(1e18)
            .add(_users[account].rewards);
    }

    function stake(uint256 amount) external override nonReentrant whenNotPaused updateReward(msg.sender) {
        require(amount > 0, "Stake: Cannot stake 0");
        _stake(amount);
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    function _stake(uint256 amount) internal {
        _totalStakes = _totalStakes.add(amount);
        User storage user = _users[msg.sender];
        user.balance = user.balance.add(amount);
        if (user.stakingTime == 0) user.stakingTime = block.timestamp;
    }

    function unstake(uint256 amount) public override nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Stake: Cannot unstake 0");
        _totalStakes = _totalStakes.sub(amount);
        User storage user = _users[msg.sender];
        user.balance = user.balance.sub(amount);
        uint256 penaltyFee = calculateFee(user.stakingTime);
        uint256 feeAmount = amount.mul(penaltyFee).div(100);
        stakingToken.safeTransfer(feeBeneficiary, feeAmount);
        stakingToken.safeTransfer(msg.sender, amount.sub(feeAmount));
        if (user.balance == 0) user.stakingTime = 0;
        emit Unstake(msg.sender, amount);
    }

    function claimReward() public override nonReentrant updateReward(msg.sender) {
        uint256 reward = _users[msg.sender].rewards;
        if (reward > 0) {
            _users[msg.sender].rewards = 0;
            rewardsToken.safeTransferFrom(rewardsTreasury, msg.sender, reward);
            emit ClaimReward(msg.sender, reward);
        }
    }

    function compoundInterest() external override nonReentrant updateReward(msg.sender) {
        require(stakingToken == rewardsToken, "Stake: Cannot compound interest different token");
        uint256 reward = _users[msg.sender].rewards;
        if (reward > 0) {
            _users[msg.sender].rewards = 0;
            _stake(reward);
            rewardsToken.safeTransferFrom(rewardsTreasury, address(this), reward);
        }
    }

    function calculateFee(uint256 timestamp) internal view returns (uint256) {
        uint256 stakedDays = (timestamp - block.timestamp).div(86400);
        if (stakedDays >= MIN_STAKE_DAYS) return 0;
        return MIN_STAKE_DAYS.sub(stakedDays);
    }

    function exit() external override nonReentrant {
        unstake(_users[msg.sender].balance);
        claimReward();
    }

    function openCampaign(uint256 _periodStart, uint256 _periodFinish, uint256 _rewardAmount) external override onlyRewardsAdministrator updateReward(address(0)) {
        require((_periodStart >= block.timestamp || (_periodStart == periodStart && _rewardAmount == rewardAmount)) && _periodFinish > _periodStart, "Stake: Invalid time!");
        
        uint256 rewardsDuration;

        // not start yet, or already finished
        if(periodStart > block.timestamp || periodFinish <= block.timestamp) {
            rewardsDuration = _periodFinish.sub(_periodStart);
            periodStart = _periodStart;
            periodFinish = _periodFinish;
            rewardAmount = _rewardAmount;
            rewardRate = _rewardAmount.div(rewardsDuration);
        } else {
            rewardsDuration = _periodFinish.sub(block.timestamp);
            uint256 remaining = periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(rewardRate);
            rewardRate = _rewardAmount.add(leftover).div(rewardsDuration);
            periodFinish = _periodFinish;
        }

        lastUpdateTime = block.timestamp;
        emit OpenCampaign(_periodStart, _periodFinish, _rewardAmount);
    }

    function withdrawReflection() external onlyOwner {
        uint256 balance = stakingToken.balanceOf(address(this));
        stakingToken.safeTransferFrom(address(this), msg.sender, balance.sub(_totalStakes));
    }
}
