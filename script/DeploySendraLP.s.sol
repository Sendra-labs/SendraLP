// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { console } from "forge-std/Script.sol";
import { LiquidityManagerV3 } from "../src/core/uniswap/executors/LiquidityManagerV3.sol";
import { LiquidityManagerV4 } from "../src/core/uniswap/executors/LiquidityManagerV4.sol";
import { LiquidityOrchestrator } from "../src/core/uniswap/executors/LiquidityOrchestrator.sol";
import { SwapRouter } from "../src/core/uniswap/executors/SwapRouter.sol";
import { LpAccounts } from "../src/storage/LpAccounts.sol";
import { AdminQuorum, IQuorumProvider, IQuorumRoles } from "./AdminQuorum.sol";

/// @notice Deploys Sendra LP and registers it with three admins.
///         The spot account is the LP account when it implements lpEnabled.
///         Requires ADDRESS_PROVIDER and HOT_ADMIN1/2/3_PRIVATE_KEY.
///         AccountsManager, AccountAccessControl, SendraStorage, PositionInitializer and Roles
///         must already be registered.
contract DeploySendraLP is AdminQuorum {
    address constant V3_POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address constant V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address constant V4_POOL_MANAGER = 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32;
    address constant V4_POSITION_MANAGER = 0xd88F38F930b7952f2DB2432Cb002E7abbF3dD869;
    address constant UNIVERSAL_ROUTER_V4 = 0x2d01411773c8C24805306E89A41F7855C3c4Fe65;

    function run() public {
        if (block.chainid != 42161) revert WrongChain();
        IQuorumProvider provider = _provider();
        IQuorumRoles roles = IQuorumRoles(provider.getAddress("Roles"));
        uint256 deployerKey = _keys()[0];

        provider.getAddress("SendraStorage");
        provider.getAddress("PositionInitializer");
        provider.getAddress("AccountsManager");
        provider.getAddress("AccountAccessControl");

        _ensure(provider, "UniswapNFTPositionManager", V3_POSITION_MANAGER);
        _ensure(provider, "UniswapV3Factory", V3_FACTORY);
        _ensure(provider, "UniswapV4PoolManager", V4_POOL_MANAGER);
        _ensure(provider, "UniswapV4PositionManager", V4_POSITION_MANAGER);

        vm.startBroadcast(deployerKey);
        LiquidityManagerV3 managerV3 = new LiquidityManagerV3(address(provider));
        LiquidityManagerV4 managerV4 = new LiquidityManagerV4(address(provider));
        SwapRouter router = new SwapRouter(UNIVERSAL_ROUTER_V4);
        LpAccounts accounts = new LpAccounts(address(provider));
        vm.stopBroadcast();

        _propose(provider, "LiquidityManager", address(managerV3));
        _propose(provider, "LiquidityManagerV4", address(managerV4));
        _propose(provider, "SwapRouter", address(router));
        _register(provider, roles, "LpAccounts", address(accounts));

        vm.startBroadcast(deployerKey);
        LiquidityOrchestrator orchestrator = new LiquidityOrchestrator(address(provider));
        vm.stopBroadcast();
        _register(provider, roles, "LiquidityOrchestrator", address(orchestrator));

        console.log("LiquidityManagerV3", address(managerV3));
        console.log("LiquidityManagerV4", address(managerV4));
        console.log("SwapRouter", address(router));
        console.log("LpAccounts", address(accounts));
        console.log("LiquidityOrchestrator", address(orchestrator));
    }

    error WrongChain();
}
