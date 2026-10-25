// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IPositionInitializer {
    function initializePosition(bytes[] memory newPositionData, uint128 positionType, address user) external;
}
