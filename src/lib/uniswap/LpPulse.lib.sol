// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ISendraStorage} from "../../interfaces/iSendraCore/ISendraStorage.sol";
import {LpData} from "./LpData.sol";

library LpPulse {
    function onOpen(ISendraStorage store, address user, uint256 capital) internal {
        uint8[] memory gFieldIds = new uint8[](5);
        int256[] memory gDeltas = new int256[](5);
        uint8[] memory sFieldIds = new uint8[](2);
        int256[] memory sDeltas = new int256[](2);

        uint256 peak = uint256(store.getUniqueGlobalAccumulator(2, user));
        uint256 exposure = uint256(store.getUniqueGlobalAccumulator(3, user));
        uint256 last = uint256(store.getUniqueGlobalAccumulator(15, user));
        uint256 nextExposure = exposure + capital;

        gFieldIds[0] = 0;
        gDeltas[0] = int256(capital);
        gFieldIds[1] = 2;
        gDeltas[1] = nextExposure > peak ? int256(nextExposure - peak) : int256(0);
        gFieldIds[2] = 3;
        gDeltas[2] = int256(capital);
        gFieldIds[3] = 9;
        gDeltas[3] = 1;
        gFieldIds[4] = 15;
        gDeltas[4] = int256(block.timestamp - last);

        sFieldIds[0] = 1;
        sDeltas[0] = int256(capital);
        sFieldIds[1] = 5;
        sDeltas[1] = 1;

        store.applyGlobalPulseDeltas(user, gFieldIds, gDeltas);
        store.applySpecificPulseDeltas(user, uint64(LpData.POSITION_TYPE), sFieldIds, sDeltas);
    }

    function onClose(
        ISendraStorage store,
        address user,
        int256 pnl,
        uint256 capitalOut,
        uint256 initialUsdc,
        uint256 openedAt
    ) internal {
        uint8[] memory gFieldIds = new uint8[](14);
        int256[] memory gDeltas = new int256[](14);
        uint8[] memory sFieldIds = new uint8[](3);
        int256[] memory sDeltas = new int256[](3);

        int256 highWaterMark = store.getUniqueGlobalAccumulator(7, user);
        int256 currentPnl = store.getUniqueGlobalAccumulator(4, user);
        int256 newPnl = currentPnl + pnl;
        int256 maxDrawdown = store.getUniqueGlobalAccumulator(8, user);
        int256 consecutiveLosses = store.getUniqueGlobalAccumulator(17, user);
        int256 maxConsecutiveLosses = store.getUniqueGlobalAccumulator(18, user);
        uint256 last = uint256(store.getUniqueGlobalAccumulator(15, user));

        gFieldIds[0] = 1;
        gDeltas[0] = int256(capitalOut);
        gFieldIds[1] = 3;
        gDeltas[1] = -int256(initialUsdc);
        gFieldIds[2] = 4;
        gDeltas[2] = pnl;
        gFieldIds[4] = 7;
        gFieldIds[5] = 8;
        gFieldIds[6] = 10;
        gDeltas[6] = 1;
        gFieldIds[7] = 11;
        gFieldIds[8] = 12;

        if (pnl > 0) {
            gFieldIds[3] = 5;
            gDeltas[3] = pnl;
            gDeltas[4] = highWaterMark < newPnl ? newPnl - highWaterMark : int256(0);
            gDeltas[5] = 0;
            gDeltas[7] = 1;
            gDeltas[8] = 0;
        } else {
            gFieldIds[3] = 6;
            gDeltas[3] = -pnl;
            gDeltas[4] = 0;
            int256 drawdown = newPnl < highWaterMark ? highWaterMark - newPnl : int256(0);
            gDeltas[5] = maxDrawdown < drawdown ? drawdown - maxDrawdown : int256(0);
            gDeltas[7] = 0;
            gDeltas[8] = 1;
        }

        gFieldIds[9] = 13;
        gDeltas[9] = int256(block.timestamp - openedAt);
        gFieldIds[10] = 15;
        gDeltas[10] = int256(block.timestamp - last);
        gFieldIds[11] = 17;
        gFieldIds[12] = 18;
        gFieldIds[13] = 19;

        if (pnl < 0) {
            int256 streak = consecutiveLosses + 1;
            gDeltas[11] = 1;
            gDeltas[12] = streak > maxConsecutiveLosses ? streak - maxConsecutiveLosses : int256(0);
            gDeltas[13] = int256(initialUsdc);
        } else if (pnl > 0) {
            gDeltas[11] = consecutiveLosses > 0 ? -consecutiveLosses : int256(0);
            gDeltas[12] = 0;
            gDeltas[13] = 0;
        }

        sFieldIds[0] = 0;
        sDeltas[0] = pnl;
        sFieldIds[1] = 2;
        sDeltas[1] = int256(capitalOut);
        if (pnl > 0) {
            sFieldIds[2] = 3;
            sDeltas[2] = 1;
        } else if (pnl < 0) {
            sFieldIds[2] = 4;
            sDeltas[2] = 1;
        }

        store.applyGlobalPulseDeltas(user, gFieldIds, gDeltas);
        store.applySpecificPulseDeltas(user, uint64(LpData.POSITION_TYPE), sFieldIds, sDeltas);
        store.applyMetricDelta(user, uint64(LpData.POSITION_TYPE), 1, int256(block.timestamp - openedAt));
    }
}
