// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FullMath} from "./FullMath.sol";

/// @notice Token amounts <-> liquidity for a Uniswap v3/v4 range. Rounds down.
library LiquidityAmounts {
    uint256 internal constant Q96 = 2 ** 96;

    function getLiquidityForAmounts(
        uint160 sqrtPrice,
        uint160 sqrtA,
        uint160 sqrtB,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint128 liquidity) {
        if (sqrtA > sqrtB) (sqrtA, sqrtB) = (sqrtB, sqrtA);
        if (sqrtPrice <= sqrtA) {
            liquidity = getLiquidityForAmount0(sqrtA, sqrtB, amount0);
        } else if (sqrtPrice < sqrtB) {
            uint128 liquidity0 = getLiquidityForAmount0(sqrtPrice, sqrtB, amount0);
            uint128 liquidity1 = getLiquidityForAmount1(sqrtA, sqrtPrice, amount1);
            liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;
        } else {
            liquidity = getLiquidityForAmount1(sqrtA, sqrtB, amount1);
        }
    }

    function getAmountsForLiquidity(uint160 sqrtPrice, uint160 sqrtA, uint160 sqrtB, uint128 liquidity)
        internal
        pure
        returns (uint256 amount0, uint256 amount1)
    {
        if (sqrtA > sqrtB) (sqrtA, sqrtB) = (sqrtB, sqrtA);
        if (sqrtPrice <= sqrtA) {
            amount0 = getAmount0ForLiquidity(sqrtA, sqrtB, liquidity);
        } else if (sqrtPrice < sqrtB) {
            amount0 = getAmount0ForLiquidity(sqrtPrice, sqrtB, liquidity);
            amount1 = getAmount1ForLiquidity(sqrtA, sqrtPrice, liquidity);
        } else {
            amount1 = getAmount1ForLiquidity(sqrtA, sqrtB, liquidity);
        }
    }

    function getLiquidityForAmount0(uint160 sqrtA, uint160 sqrtB, uint256 amount0) internal pure returns (uint128) {
        if (sqrtA > sqrtB) (sqrtA, sqrtB) = (sqrtB, sqrtA);
        uint256 intermediate = FullMath.mulDiv(sqrtA, sqrtB, Q96);
        return _toUint128(FullMath.mulDiv(amount0, intermediate, sqrtB - sqrtA));
    }

    function getLiquidityForAmount1(uint160 sqrtA, uint160 sqrtB, uint256 amount1) internal pure returns (uint128) {
        if (sqrtA > sqrtB) (sqrtA, sqrtB) = (sqrtB, sqrtA);
        return _toUint128(FullMath.mulDiv(amount1, Q96, sqrtB - sqrtA));
    }

    function getAmount0ForLiquidity(uint160 sqrtA, uint160 sqrtB, uint128 liquidity) internal pure returns (uint256) {
        if (sqrtA > sqrtB) (sqrtA, sqrtB) = (sqrtB, sqrtA);
        return FullMath.mulDiv(uint256(liquidity) << 96, sqrtB - sqrtA, sqrtB) / sqrtA;
    }

    function getAmount1ForLiquidity(uint160 sqrtA, uint160 sqrtB, uint128 liquidity) internal pure returns (uint256) {
        if (sqrtA > sqrtB) (sqrtA, sqrtB) = (sqrtB, sqrtA);
        return FullMath.mulDiv(liquidity, sqrtB - sqrtA, Q96);
    }

    function _toUint128(uint256 x) private pure returns (uint128 y) {
        require(x <= type(uint128).max);
        y = uint128(x);
    }
}
