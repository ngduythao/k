// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";

abstract contract RewardsAdministrator is Ownable {
    event RewardsTreasuryUpdated(address indexed treasury);

    address public rewardsAdministrator;
    address public rewardsTreasury;

    function addRewards(uint256 rewardsAmount) external virtual;
    
    modifier onlyRewardsAdministrator() {
        require(msg.sender == rewardsAdministrator, "Administrator: Caller is not an administrator");
        _;
    }

    function setRewardsAdministrator(address newAdministrator) external virtual onlyOwner {
        rewardsAdministrator = newAdministrator;
    }

    function setRewardsTreasury(address newTreasury) external virtual onlyRewardsAdministrator {
        require(newTreasury != address(0), "Administrator: Treasury cannot be address 0");
        rewardsTreasury = newTreasury;
        emit RewardsTreasuryUpdated(newTreasury);
    }
}