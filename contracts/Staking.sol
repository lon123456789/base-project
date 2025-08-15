a// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Inline IERC20 interface
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

/**
 * @title GigaStacking
 * @dev A basic staking contract where users stake tokens to earn rewards over time.
 * Rewards are calculated based on staking duration and a fixed reward rate.
 * Deploy on Base; verify as single-file on Basescan.
 */
contract Projectstaking  {
    IERC20 public stakingToken; // Token to stake (ERC20)
    IERC20 public rewardToken;  // Token for rewards (can be same as stakingToken)

    uint256 public rewardRate; // Reward tokens per second per staked token (e.g., 1e18 for 1:1)
    uint256 public totalStaked;

    struct Stake {
        uint256 amount;
        uint256 timestamp;
        uint256 accumulatedRewards;
    }

    mapping(address => Stake) public stakes;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount, uint256 rewards);
    event RewardsClaimed(address indexed user, uint256 rewards);

    /**
     * @dev Constructor to set staking and reward tokens, and reward rate.
     * @param _stakingToken Address of the ERC20 token to stake.
     * @param _rewardToken Address of the ERC20 token for rewards.
     * @param _rewardRate Reward rate per second per staked token (scaled by 1e18 for precision).
     */
    constructor(address _stakingToken, address _rewardToken, uint256 _rewardRate) {
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        rewardRate = _rewardRate;
    }

    /**
     * @dev Calculate pending rewards for a user.
     * @param user Address of the staker.
     * @return Pending rewards.
     */
    function pendingRewards(address user) public view returns (uint256) {
        Stake storage userStake = stakes[user];
        if (userStake.amount == 0) return 0;
        uint256 timeStaked = block.timestamp - userStake.timestamp;
        uint256 newRewards = (userStake.amount * rewardRate * timeStaked) / 1e18;
        return userStake.accumulatedRewards + newRewards;
    }

    /**
     * @dev Stake tokens.
     * @param amount Amount to stake.
     */
    function stake(uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");
        _updateRewards(msg.sender);
        stakingToken.transferFrom(msg.sender, address(this), amount);
        stakes[msg.sender].amount += amount;
        totalStaked += amount;
        emit Staked(msg.sender, amount);
    }

    /**
     * @dev Unstake tokens and claim rewards.
     * @param amount Amount to unstake.
     */
    function unstake(uint256 amount) external {
        require(amount > 0 && amount <= stakes[msg.sender].amount, "Invalid amount");
        _updateRewards(msg.sender);
        uint256 rewards = stakes[msg.sender].accumulatedRewards;
        stakes[msg.sender].accumulatedRewards = 0;
        stakes[msg.sender].amount -= amount;
        totalStaked -= amount;
        stakingToken.transfer(msg.sender, amount);
        if (rewards > 0) {
            rewardToken.transfer(msg.sender, rewards);
        }
        emit Unstaked(msg.sender, amount, rewards);
    }

    /**
     * @dev Claim pending rewards without unstaking.
     */
    function claimRewards() external {
        _updateRewards(msg.sender);
        uint256 rewards = stakes[msg.sender].accumulatedRewards;
        require(rewards > 0, "No rewards to claim");
        stakes[msg.sender].accumulatedRewards = 0;
        rewardToken.transfer(msg.sender, rewards);
        emit RewardsClaimed(msg.sender, rewards);
    }

    /**
     * @dev Internal function to update accumulated rewards.
     * @param user Address of the staker.
     */
    function _updateRewards(address user) internal {
        Stake storage userStake = stakes[user];
        if (userStake.amount > 0) {
            uint256 timeStaked = block.timestamp - userStake.timestamp;
            uint256 newRewards = (userStake.amount * rewardRate * timeStaked) / 1e18;
            userStake.accumulatedRewards += newRewards;
            userStake.timestamp = block.timestamp;
        }
    }
}



