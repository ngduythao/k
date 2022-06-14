// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;
interface IRouter {
    function getAmountsOut(uint amountIn, address[] memory path) external view returns (uint[] memory amounts);
}
