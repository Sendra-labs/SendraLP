// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {TickMath} from "@uniswap/v4-core/libraries/TickMath.sol";
import {LiquidityAmounts} from "../src/lib/uniswap/LiquidityAmounts.sol";

contract LiquidityAmountsTest is Test {
    function test_tickZeroPrice() public pure {
        assertEq(TickMath.getSqrtPriceAtTick(0), 79228162514264337593543950336);
    }

    function test_roundTripInsideRange() public pure {
        uint160 price = TickMath.getSqrtPriceAtTick(0);
        uint160 lower = TickMath.getSqrtPriceAtTick(-600);
        uint160 upper = TickMath.getSqrtPriceAtTick(600);
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(price, lower, upper, 1 ether, 1 ether);
        assertGt(liquidity, 0);
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(price, lower, upper, liquidity);
        assertLe(amount0, 1 ether);
        assertLe(amount1, 1 ether);
        assertGt(amount0, 0);
        assertGt(amount1, 0);
    }
}
