// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {LiquidityOrchestrator} from "../src/core/uniswap/executors/LiquidityOrchestrator.sol";

interface ICellWithdraw {
    function withdrawLiquidityAndCollectFees(LiquidityOrchestrator.AaveExecuteWithdraw calldata input)
        external
        returns (uint256);
}

/// @dev The deployed lending cell calls this selector. Spot uses the uint256 overload.
contract AaveWithdrawSelectorTest is Test {
    function test_matchesLendingCell() public pure {
        assertEq(ICellWithdraw.withdrawLiquidityAndCollectFees.selector, hex"d499505a");
    }
}
