// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { console } from "forge-std/Script.sol";
import { LiquidityOrchestrator } from "../src/core/uniswap/executors/LiquidityOrchestrator.sol";
import { AdminQuorum, IQuorumProvider, IQuorumRoles } from "./AdminQuorum.sol";

/// @notice Replaces LiquidityOrchestrator. Spot LP keeps using LpAccounts.
///         An Aave lending cell is a different account, and borrow-to-LP is
///         allowed when that cell is a protocol account owned by the user.
///         Managers read "LiquidityOrchestrator" from the provider, so
///         registering this replacement is enough.
contract RedeployLiquidityOrchestrator is AdminQuorum {
    function run() public {
        if (block.chainid != 42161) revert WrongChain();
        IQuorumProvider provider = _provider();
        IQuorumRoles roles = IQuorumRoles(provider.getAddress("Roles"));
        provider.getAddress("SwapRouter");
        provider.getAddress("LiquidityManager");
        provider.getAddress("LiquidityManagerV4");
        provider.getAddress("SendraStorage");
        provider.getAddress("PositionInitializer");
        provider.getAddress("LpAccounts");

        vm.startBroadcast(_keys()[0]);
        LiquidityOrchestrator orchestrator = new LiquidityOrchestrator(address(provider));
        vm.stopBroadcast();

        _register(provider, roles, "LiquidityOrchestrator", address(orchestrator));
        console.log("LiquidityOrchestrator", address(orchestrator));
        console.log("swapRouter", address(orchestrator.swapRouter()));
    }

    error WrongChain();
}
