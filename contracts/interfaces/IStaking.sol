// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

interface IStaking {
    function stake(uint256 amount) external;

    function unstake(uint256 amount) external;

    function claimReward() external;

    function compoundInterest() external;

    function exit() external;

    function totalStakes() external view returns (uint256);
    
    function getUserInfo(address account) external view returns (uint256, uint256, uint256, uint256);

    function earned(address account) external view returns (uint256);

    function lastUpdated() external view returns (uint256);

    function rewardPerToken() external view returns (uint256);

    function getApr() external view returns(uint256);

    function getRemainingReward() external view returns(uint256);
}
