// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";
import '@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol';
import "./utils/Ownable.sol";

// This needs WORK.

contract Staking is Ownable {
    using SafeMath for uint256;

    struct Deposit {
        uint256 tokenAmount;
        uint256 weight;
        uint256 lockedUntil;
        uint256 baseFactor;
        uint256 rewardFactor;
    }

    struct UserInfo {
        uint256 tokenAmount;
        uint256 totalWeight;
        uint256 totalClaimedBase;
        uint256 totalClaimedReward;
        Deposit[] deposits;
    }

    uint256 public constant ONE_DAY = 1 days;
    uint256 public constant LOCK_DUR_MIN = 7 * ONE_DAY;
    uint256 public constant LOCK_DUR_MID = 14 * ONE_DAY;
    uint256 public constant LOCK_DUR_MAX = 31 * ONE_DAY;
    uint256 public constant TOTAL_LOCK_MODES = 3;

    // total locked amount across all users
    uint256 public usersLockingAmount;
    // total locked weight across all users
    uint256 public usersLockingWeight;

    // The base & reward token
    IBEP20 public immutable token;
    IBEP20 public immutable rewardToken;

    // the reward rates
    uint256 public rateMin;
    uint256 public rateMid;
    uint256 public rateMax;

    uint256 private _totalSupplyBase;
    uint256 private _totalSupplyReward;

    mapping(address => uint256) private _balanceBase;
    mapping(address => uint256) private _balanceReward;

    // Info of each user that stakes LP tokens.
    mapping(address => UserInfo) public userInfo;

    event Staked(address indexed user, uint256 amount, uint256 lockMode);
    event Unstaked(address indexed user, uint256 amountBase, uint256 amountReward);
    event Claimed(address indexed user, uint256 amountReward);

    constructor(address _token, address _rewardToken) public {
        token = IBEP20(_token);
        rewardToken = IBEP20(_rewardToken);
    }

    // Returns total staked token balance for the given address
    function balanceOf(address _user) external view returns (uint256) {
        return userInfo[_user].tokenAmount;
    }

    // Returns total staked token weight for the given address
    function weightOf(address _user) external view returns (uint256) {
        return userInfo[_user].totalWeight;
    }

    // Returns information on the given deposit for the given address
    function getDeposit(address _user, uint256 _depositId) external view returns (
        uint256 tokenAmount,
        uint256 weight,
        uint256 lockedUntil,
        uint256 baseFactor,
        uint256 rewardFactor
    ) {
        Deposit memory stakeDeposit = userInfo[_user].deposits[_depositId];
        tokenAmount = stakeDeposit.tokenAmount;
        weight = stakeDeposit.weight;
        lockedUntil = stakeDeposit.lockedUntil;
        baseFactor = stakeDeposit.baseFactor;
        rewardFactor = stakeDeposit.rewardFactor;
    }

    // Returns number of deposits for the given address. Allows iteration over deposits.
    function getDepositsLength(address _user) external view returns (uint256) {
        return userInfo[_user].deposits.length;
    }

    function getPendingRewardOf(address _staker, uint256 _depositId) external view returns(uint256 whatBase, uint256 whatReward) {
        UserInfo storage user = userInfo[_staker];
        Deposit storage stakeDeposit = user.deposits[_depositId];

        uint256 amount = stakeDeposit.tokenAmount;
        uint256 baseF = stakeDeposit.baseFactor;
        uint256 rewardF = stakeDeposit.rewardFactor;

        require(amount > 0, "Staking: Deposit amount is 0");

        uint256 totalTokenBase = token.balanceOf(address(this));
        uint256 totalSharesBase = _totalSupplyBase;

        uint256 totalTokenReward = rewardToken.balanceOf(address(this));
        uint256 totalSharesReward = _totalSupplyReward;

        whatBase = (baseF * totalTokenBase) / totalSharesBase;
        whatReward = (rewardF * totalTokenReward) / totalSharesReward;
    }

    function getUnlockSpecs(uint256 _amount, uint256 _lockMode) public view returns(uint256 lockUntil, uint256 weight) {
        require(_lockMode < TOTAL_LOCK_MODES, "Staking: Invalid lock mode");

        if(_lockMode == 0) {
            // 0 : 7-day lock
            return (now256() + LOCK_DUR_MIN * ONE_DAY, (_amount * (100 + rateMin)) / 100);
        }
        else if(_lockMode == 1) {
            // 1 : 14-day lock
            return (now256() + LOCK_DUR_MID * ONE_DAY, (_amount * (100 + rateMid)) / 100);
        }

        // 2 : 31-day lock
        return (now256() + LOCK_DUR_MAX * ONE_DAY, (_amount * (100 + rateMax)) / 100);
    }

    function now256() public view returns (uint256) {
        // return current block timestamp
        return block.timestamp;
    }

    function updateRates(uint256 _rateMin, uint256 _rateMid, uint256 _rateMax) external onlyOwner {
        require(_rateMin < 100, "Staking: Invalid rate");
        require(_rateMid < 100, "Staking: Invalid rate");
        require(_rateMax < 100, "Staking: Invalid rate");
        rateMin = _rateMin;
        rateMid = _rateMid;
        rateMax = _rateMax;
    }
    // Added to support recovering lost tokens that find their way to this contract
    function recoverERC20(address _tokenAddress, uint256 _tokenAmount) external onlyOwner {
        require(_tokenAddress != address(token), "Staking: Cannot withdraw the staking token");
        require(_tokenAddress != address(rewardToken), "Staking: Cannot withdraw the reward token");
        IBEP20(_tokenAddress).transfer(msg.sender, _tokenAmount);
    }

    // Stake tokens
    function stake(uint256 _amount, uint256 _lockMode) external {
        _stake(msg.sender, _amount, _lockMode);
    }

    // Unstake tokens and claim rewards
    function unstake(uint256 _depositId) external {
        _unstake(msg.sender, _depositId);
    }

    // Claim rewards
    function claimRewards(uint256 _depositId) external {
        _claimRewards(msg.sender, _depositId);
    }

    function claimRewardsBatch(uint256[] calldata _depositIds) external {
        for(uint256 i = 0; i < _depositIds.length; i++) {
            _claimRewards(msg.sender, _depositIds[i]);
        }
    }

    function _stake(address _staker, uint256 _amount, uint256 _lockMode) internal {
        require(_amount > 0, "Staking: Deposit amount is 0");

        uint256 totalTokenBase = token.balanceOf(address(this));
        uint256 totalSharesBase = _totalSupplyBase;

        uint256 totalTokenReward = rewardToken.balanceOf(address(this));
        uint256 totalSharesReward = _totalSupplyReward;

        uint256 actualAmount = _transferTokenFrom(address(_staker), address(this), _amount);
        (uint256 lockUntil, uint256 scaledAmount) = getUnlockSpecs(actualAmount, _lockMode);

        uint256 whatBase;
        uint256 whatReward;

        if (totalSharesBase == 0 || totalTokenBase == 0) {
            whatBase = scaledAmount;
        } else {
            whatBase = scaledAmount.mul(totalSharesBase).div(totalTokenBase);
        }

        if (totalSharesReward == 0 || totalTokenReward == 0) {
            whatReward = scaledAmount;
        } else {
            whatReward = scaledAmount.mul(totalSharesReward).div(totalTokenReward);
        }

        // create and save the deposit (append it to deposits array)
        Deposit memory deposit =
            Deposit({
                tokenAmount: actualAmount,
                weight: scaledAmount,
                lockedUntil: lockUntil,
                baseFactor: whatBase,
                rewardFactor: whatReward
            });

        // deposit ID is an index of the deposit in `deposits` array
        UserInfo storage user = userInfo[_staker];
        user.deposits.push(deposit);

        user.tokenAmount = user.tokenAmount.add(actualAmount);
        user.totalWeight = user.totalWeight.add(scaledAmount);

        // update global variable
        usersLockingAmount = usersLockingAmount.add(actualAmount);
        usersLockingWeight = usersLockingWeight.add(scaledAmount);

        _mintBase(_staker, whatBase);
        _mintReward(_staker, whatReward);

        emit Staked(_staker, actualAmount, _lockMode);
    }

    function _unstake(address _staker, uint256 _depositId) internal {
        UserInfo storage user = userInfo[_staker];
        Deposit storage stakeDeposit = user.deposits[_depositId];

        uint256 amount = stakeDeposit.tokenAmount;
        uint256 scaledAmount = stakeDeposit.weight;
        uint256 baseF = stakeDeposit.baseFactor;
        uint256 rewardF = stakeDeposit.rewardFactor;

        require(amount > 0, "Staking: Deposit amount is 0");
        require(now256() > stakeDeposit.lockedUntil, "Staking: Deposit not unlocked yet");

        uint256 totalTokenBase = token.balanceOf(address(this));
        uint256 totalSharesBase = _totalSupplyBase;

        uint256 totalTokenReward = rewardToken.balanceOf(address(this));
        uint256 totalSharesReward = _totalSupplyReward;

        uint256 whatBase = baseF.mul(totalTokenBase).div(totalSharesBase);
        uint256 whatReward = rewardF.mul(totalTokenReward).div(totalSharesReward);

        // update user record
        user.tokenAmount = user.tokenAmount.sub(amount);
        user.totalWeight = user.totalWeight.sub(scaledAmount);
        user.totalClaimedBase = user.totalClaimedBase.add(whatBase.sub(amount));
        user.totalClaimedReward = user.totalClaimedReward.add(whatReward);

        // update global variable
        usersLockingAmount = usersLockingAmount.sub(amount);
        usersLockingWeight = usersLockingWeight.sub(scaledAmount);

        delete user.deposits[_depositId];

        _burnBase(_staker, baseF);
        _burnReward(_staker, rewardF);

        // return tokens back to holder
        _safeTokenTransfer(token, _staker, whatBase);
        _safeTokenTransfer(rewardToken, _staker, whatReward);

        emit Unstaked(_staker, whatBase, whatReward);
    }

    function _claimRewards(address _staker, uint256 _depositId) internal {
        UserInfo storage user = userInfo[_staker];
        Deposit storage stakeDeposit = user.deposits[_depositId];

        uint256 amount = stakeDeposit.tokenAmount;
        uint256 scaledAmount = stakeDeposit.weight;
        uint256 rewardF = stakeDeposit.rewardFactor;

        require(amount > 0, "Staking: Deposit amount is 0");

        uint256 totalTokenReward = rewardToken.balanceOf(address(this));
        uint256 totalSharesReward = _totalSupplyReward;

        uint256 whatReward = (rewardF * totalTokenReward) / totalSharesReward;
        _burnReward(_staker, rewardF);

        // return tokens back to holder
        _safeTokenTransfer(rewardToken, _staker, whatReward);

        // update user record
        user.totalClaimedReward += whatReward;

        // calculate new reward units
        totalTokenReward = rewardToken.balanceOf(address(this));
        totalSharesReward = _totalSupplyReward;
        uint256 newReward;
        if (totalSharesReward == 0 || totalTokenReward == 0) {
            newReward = scaledAmount;
        } else {
            newReward = (scaledAmount * totalSharesReward) / totalTokenReward;
        }

        // update stakeDeposit record
        stakeDeposit.rewardFactor = newReward;

        emit Claimed(_staker, whatReward);
    }

    function _transferTokenFrom(address _from, address _to, uint256 _value) internal returns(uint256) {
        uint256 balanceBefore = token.balanceOf(address(this));
        token.transferFrom(_from, _to, _value);
        return token.balanceOf(address(this)) - balanceBefore;
    }

    // Safe token transfer function, just in case if rounding error causes contract to not have enough tokens.
    function _safeTokenTransfer(IBEP20 _token, address _to, uint256 _amount) internal {
        uint256 tokenBal = _token.balanceOf(address(this));
        if (_amount > tokenBal) {
            _token.transfer(_to, tokenBal);
        } else {
            _token.transfer(_to, _amount);
        }
    }

    function _mintBase(address _staker, uint256 _amount) internal {
        _balanceBase[_staker] += _amount;
        _totalSupplyBase += _amount;
    }

    function _mintReward(address _staker, uint256 _amount) internal {
        _balanceReward[_staker] += _amount;
        _totalSupplyReward += _amount;
    }

    function _burnBase(address _staker, uint256 _amount) internal {
        _balanceBase[_staker] -= _amount;
        _totalSupplyBase -= _amount;
    }

    function _burnReward(address _staker, uint256 _amount) internal {
        _balanceReward[_staker] -= _amount;
        _totalSupplyReward -= _amount;
    }
}
