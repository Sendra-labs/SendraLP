// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @dev ABI-compatible with protocol `SendraLib.Position` and `UserInfoRead`.
library SendraLib {
    struct Position {
        uint128 positionType;
        uint256 id;
        int256 pnl;
        bool isActive;
        bytes[] positionData;
    }

    struct UserInfoRead {
        uint256 id;
        int256 globalPnl;
        uint256 totalPositions;
        uint256 activePositions;
        uint256 transactionCount;
        bytes[] userData;
    }
}
