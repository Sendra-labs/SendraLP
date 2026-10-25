// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {UniswapLib} from "./Uniswap.lib.sol";

library SwapScale {
    error RouteMissing(address token);

    /// @dev Rescale a sell route so every root hop sums to `amount`.
    ///      Hops with amountIn 0 are intermediate steps and stay 0.
    function scale(
        UniswapLib.SwapInput memory swap,
        address tokenIn,
        address tokenOut,
        uint256 amount,
        address recipient
    ) internal pure returns (UniswapLib.SwapInput memory) {
        if (swap.tokenIn != tokenIn || swap.tokenOut != tokenOut) revert RouteMissing(tokenIn);

        uint256 n = swap.swapInstructions.length;
        uint256 weight = 0;
        uint256 roots = 0;
        for (uint256 i = 0; i < n; i++) {
            if (swap.swapInstructions[i].amountIn > 0) {
                weight += swap.swapInstructions[i].amountIn;
                roots++;
            }
        }
        if (weight == 0 || roots == 0) revert RouteMissing(tokenIn);

        uint256[] memory scaled = new uint256[](n);
        uint256 assigned = 0;
        uint256 seen = 0;
        for (uint256 i = 0; i < n; i++) {
            uint256 hopIn = swap.swapInstructions[i].amountIn;
            if (hopIn == 0) continue;
            seen++;
            uint256 part = seen == roots ? amount - assigned : (amount * hopIn) / weight;
            scaled[i] = part;
            assigned += part;
        }

        uint256 outLen = 0;
        for (uint256 i = 0; i < n;) {
            if (swap.swapInstructions[i].amountIn == 0) {
                i++;
                continue;
            }
            if (scaled[i] == 0) {
                i++;
                while (i < n && swap.swapInstructions[i].amountIn == 0) i++;
                continue;
            }
            outLen++;
            i++;
            while (i < n && swap.swapInstructions[i].amountIn == 0) {
                outLen++;
                i++;
            }
        }
        if (outLen == 0) revert RouteMissing(tokenIn);

        UniswapLib.SwapInstruction[] memory nextInstructions = new UniswapLib.SwapInstruction[](outLen);
        uint256 w = 0;
        for (uint256 i = 0; i < n;) {
            if (swap.swapInstructions[i].amountIn == 0) {
                i++;
                continue;
            }
            if (scaled[i] == 0) {
                i++;
                while (i < n && swap.swapInstructions[i].amountIn == 0) i++;
                continue;
            }
            uint256 origRoot = swap.swapInstructions[i].amountIn;
            uint256 part = scaled[i];
            nextInstructions[w] = swap.swapInstructions[i];
            nextInstructions[w].amountIn = part;
            nextInstructions[w].amountOut = _scaleAmountOut(nextInstructions[w].amountOut, part, origRoot);
            w++;
            i++;
            while (i < n && swap.swapInstructions[i].amountIn == 0) {
                nextInstructions[w] = swap.swapInstructions[i];
                nextInstructions[w].amountIn = 0;
                nextInstructions[w].amountOut = _scaleAmountOut(nextInstructions[w].amountOut, part, origRoot);
                w++;
                i++;
            }
        }

        swap.swapInstructions = nextInstructions;
        swap.amountIn0 = amount;
        swap.to = recipient;
        return swap;
    }

    function invert(UniswapLib.SwapInput memory input, uint256 amount, address recipient)
        internal
        pure
        returns (UniswapLib.SwapInput memory)
    {
        uint256 len = input.swapInstructions.length;
        UniswapLib.SwapInstruction[] memory inverted = new UniswapLib.SwapInstruction[](len);
        for (uint256 i = 0; i < len; i++) {
            UniswapLib.SwapInstruction memory inst = input.swapInstructions[len - 1 - i];
            inverted[i] = UniswapLib.SwapInstruction({
                protocol: inst.protocol,
                tokenIn: inst.tokenOut,
                tokenOut: inst.tokenIn,
                amountIn: (i == 0) ? amount : 0,
                amountOut: 0,
                poolOrPair: inst.poolOrPair,
                fee: inst.fee,
                poolKey: inst.poolKey
            });
        }
        return UniswapLib.SwapInput({
            tokenIn: input.tokenOut,
            tokenOut: input.tokenIn,
            swapInstructions: inverted,
            amountIn0: amount,
            to: recipient
        });
    }

    function _scaleAmountOut(uint256 amountOut, uint256 part, uint256 origRoot) private pure returns (uint256) {
        if (amountOut == 0 || origRoot == 0) return 0;
        return (amountOut * part) / origRoot;
    }
}
