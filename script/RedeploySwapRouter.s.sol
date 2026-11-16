// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { console } from "forge-std/Script.sol";
import { SwapRouter } from "../src/core/uniswap/executors/SwapRouter.sol";
import { AdminQuorum, IQuorumProvider } from "./AdminQuorum.sol";

/// @notice Replaces SwapRouter. The live Universal Router expects a sixth
///         minHopPriceX36 word on V2/V3 commands; the previous router omitted it
///         and every swap reverted with SliceOutOfBounds.
///         SwapAccountant stores the router immutably, so after this script
///         run markets/script/UpdateSwapAccountant.s.sol and point the frontend
///         at the new accountant.
contract RedeploySwapRouter is AdminQuorum {
    address constant UNIVERSAL_ROUTER_V4 = 0x2d01411773c8C24805306E89A41F7855C3c4Fe65;

    function run() public {
        if (block.chainid != 42161) revert WrongChain();
        IQuorumProvider provider = _provider();

        vm.startBroadcast(_keys()[0]);
        SwapRouter router = new SwapRouter(UNIVERSAL_ROUTER_V4);
        vm.stopBroadcast();

        _propose(provider, "SwapRouter", address(router));
        console.log("SwapRouter", address(router));
    }

    error WrongChain();
}
