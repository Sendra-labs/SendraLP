// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SendraLib} from "../../lib/Sendra.lib.sol";

interface ISendraStorage {
    function getUser(address user) external view returns (SendraLib.UserInfoRead memory);

    function updateUserFullPosition(address user, uint256 positionId, SendraLib.Position memory position) external;

    function decreaseGlobalPositionActivePositions(address user) external;

    function applyGlobalPulseDeltas(address user, uint8[] calldata fieldIds, int256[] calldata deltas) external;

    function applySpecificPulseDeltas(
        address user,
        uint64 specificKey,
        uint8[] calldata fieldIds,
        int256[] calldata deltas
    ) external;

    function applyMetricDelta(address user, uint64 specificKey, uint256 metricIndex, int256 delta) external;

    function getUniqueGlobalAccumulator(uint8 fieldId, address user) external view returns (int256);

    function getUserPositionById(address user, uint256 positionId) external view returns (SendraLib.Position memory);
}
