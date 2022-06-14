// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";

abstract contract RewardsAdministrator is Ownable {
    event RewardsTreasuryUpdated(address indexed treasury);

    address private _rewardsAdministrator;
    address private _rewardsTreasury;

    function openCampaign(uint256 periodStart, uint256 periodFinish, uint256 rewardsAmount, uint256 rewardCycle) external virtual;
    
    modifier onlyRewardsAdministrator() {
        require(msg.sender == rewardsAdministrator(), "Administrator: Caller is not an administrator");
        _;
    }

    function rewardsAdministrator() public view returns(address) {
        return _rewardsAdministrator;
    }

    function rewardsTreasury() public view returns(address) {
        return _rewardsTreasury;
    }

    function setRewardsAdministrator(address newAdministrator) external virtual onlyOwner {
        _rewardsAdministrator = newAdministrator;
    }

    function setRewardsTreasury(address newTreasury) external virtual onlyRewardsAdministrator {
        require(newTreasury != address(0), "Administrator: Treasury cannot be address 0");
        _rewardsTreasury = newTreasury;
        emit RewardsTreasuryUpdated(newTreasury);
    }
}