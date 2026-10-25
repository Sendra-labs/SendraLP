// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {UniswapLib} from "../../lib/uniswap/Uniswap.lib.sol";

interface ISwapRouter {
    function executeSwap(UniswapLib.SwapInput memory input) external;
}
