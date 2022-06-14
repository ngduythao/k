
// SPDX-License-Identifier: MIT

import "./IERC20.sol";

pragma solidity ^0.8.10;

interface IERC20Metadata is IERC20 {
    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);
}