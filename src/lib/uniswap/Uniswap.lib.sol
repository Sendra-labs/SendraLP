// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "@uniswap/v4-core/types/PoolKey.sol";

library UniswapLib {
    enum Protocol {
        UniswapV2,
        UniswapV3,
        UniswapV4
    }

    struct SwapInstruction {
        Protocol protocol;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 amountOut;
        address poolOrPair;
        uint24 fee;
        PoolKey poolKey;
    }

    struct SwapInput {
        address tokenIn;
        address tokenOut;
        SwapInstruction[] swapInstructions;
        uint256 amountIn0;
        address to;
    }

    struct ProvideLiquidityInput {
        Protocol protocol;
        address token0;
        address token1;
        address recipient;
        address user;
        uint256 amount0;
        uint256 amount1;
        int24 tickLower;
        int24 tickUpper;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
    }

    struct ExecuteProvideLiquidityInput {
        SwapInput swapInput0;
        SwapInput swapInput1;
        SwapInput invertedSwapInput0;
        SwapInput invertedSwapInput1;
        ProvideLiquidityInput provideLiquidityInput;
    }

    struct PartialCloseInput {
        uint256 uniId;
        uint256 positionId;
        address user;
    }

    struct SellHeldInput {
        uint256 positionId;
        address user;
        SwapInput swapInput0;
        SwapInput swapInput1;
    }

    struct WithdrawInput {
        uint256 uniId;
        uint256 positionId;
        address user;
    }

    struct ExecuteWithdrawLiquidityAndCollectFees {
        WithdrawInput withdrawInput;
        SwapInput swapInput0;
        SwapInput swapInput1;
    }

    struct CollectInput {
        uint256 uniId;
        uint256 positionId;
        address user;
    }

    struct ExecuteCollectFeesOnly {
        CollectInput collectInput;
        SwapInput swapInput0;
        SwapInput swapInput1;
    }

    struct MintOut {
        uint256 tokenId;
        uint256 deposited0;
        uint256 deposited1;
        uint160 sqrtPrice;
        address pool;
        bytes32 poolId;
        uint256 left0;
        uint256 left1;
    }

    struct ExitOut {
        uint256 principal0;
        uint256 principal1;
        uint256 fee0;
        uint256 fee1;
        uint160 sqrtPrice;
    }
}
