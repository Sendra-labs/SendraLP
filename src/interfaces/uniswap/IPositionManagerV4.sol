// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IPositionManagerV4 {
    function modifyLiquidities(bytes calldata unlockData, uint256 deadline) external payable;

    function nextTokenId() external view returns (uint256);

    function getPositionLiquidity(uint256 tokenId) external view returns (uint128 liquidity);
}
