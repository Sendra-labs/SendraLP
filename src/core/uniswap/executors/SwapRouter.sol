// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPermit2} from "../../../interfaces/uniswap/IPermit2.sol";
import {IUniversalRouter} from "../../../interfaces/uniswap/IUniversalRouter.sol";
import {ISwapRouter} from "../../../interfaces/uniswap/ISwapRouter.sol";
import {UniswapLib} from "../../../lib/uniswap/Uniswap.lib.sol";
import {UniswapParamsEncoderLib} from "../../../lib/uniswap/ParamsEncoder.lib.sol";

contract SwapRouter is ISwapRouter {
    using SafeERC20 for IERC20;

    IUniversalRouter public immutable universalRouter;
    IPermit2 public constant PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    constructor(address universalRouterAddress) {
        universalRouter = IUniversalRouter(universalRouterAddress);
    }

    function executeSwap(UniswapLib.SwapInput memory input) public {
        IERC20 tokenIn = IERC20(input.tokenIn);
        uint256 have = tokenIn.balanceOf(address(this));
        if (have < input.amountIn0) revert InsufficientTokenInBalance(input.tokenIn, have, input.amountIn0);

        tokenIn.forceApprove(address(PERMIT2), input.amountIn0);
        if (input.amountIn0 > type(uint160).max) revert AmountTooLarge();
        PERMIT2.approve(input.tokenIn, address(universalRouter), uint160(input.amountIn0), uint48(block.timestamp + 1 hours));
        (bytes memory commands, bytes[] memory inputs) = UniswapParamsEncoderLib.createParams(input, address(this));
        universalRouter.execute(commands, inputs);
    }

    error InsufficientTokenInBalance(address tokenIn, uint256 balance, uint256 required);
    error AmountTooLarge();
}
