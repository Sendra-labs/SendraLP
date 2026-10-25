// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {LiquidityManagerV3} from "../src/core/uniswap/executors/LiquidityManagerV3.sol";
import {LiquidityManagerV4} from "../src/core/uniswap/executors/LiquidityManagerV4.sol";
import {LiquidityOrchestrator} from "../src/core/uniswap/executors/LiquidityOrchestrator.sol";
import {SwapRouter} from "../src/core/uniswap/executors/SwapRouter.sol";
import {LpAccounts} from "../src/storage/LpAccounts.sol";

/// @notice Deploys Sendra LP on Arbitrum and registers it in the live AddressProvider.
///         One orchestrator, a v3 manager, a v4 manager, and the LP account resolver.
///         The user's spot account is the LP account when it implements lpEnabled.
///         LpAccounts only deploys a cell for an owner whose spot account cannot.
///
///         forge script script/DeploySendraLP.s.sol --rpc-url arbitrum --broadcast
///
///         Requires ADMIN1_PRIVATE_KEY (or PRIVATE_KEY) of an AddressProvider admin.
///         AccountsManager, AccountAccessControl, SendraStorage, PositionInitializer and Roles
///         must already be registered. The script points SwapRouter at Universal Router 2.1.2
///         so v4 swap command 0x10 is available.
contract DeploySendraLP is Script {
    address constant ADDRESS_PROVIDER = 0xaF7A2feFBA6Acc09e62011d0359dC06e0e1245f5;

    address constant V3_POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address constant V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address constant V4_POOL_MANAGER = 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32;
    address constant V4_POSITION_MANAGER = 0xd88F38F930b7952f2DB2432Cb002E7abbF3dD869;
    address constant UNIVERSAL_ROUTER_V4 = 0x2d01411773c8C24805306E89A41F7855C3c4Fe65;

    function run() public {
        if (block.chainid != 42161) revert WrongChain();
        uint256 pk = _privateKey();
        IProvider provider = IProvider(ADDRESS_PROVIDER);
        IRoles roles = IRoles(provider.getAddress("Roles"));

        provider.getAddress("SendraStorage");
        provider.getAddress("PositionInitializer");
        provider.getAddress("AccountsManager");
        provider.getAddress("AccountAccessControl");

        vm.startBroadcast(pk);

        _ensure(provider, "UniswapNFTPositionManager", V3_POSITION_MANAGER);
        _ensure(provider, "UniswapV3Factory", V3_FACTORY);
        provider.setAddress("UniswapV4PoolManager", V4_POOL_MANAGER);
        provider.setAddress("UniswapV4PositionManager", V4_POSITION_MANAGER);

        LiquidityManagerV3 managerV3 = new LiquidityManagerV3(ADDRESS_PROVIDER);
        provider.setAddress("LiquidityManager", address(managerV3));

        LiquidityManagerV4 managerV4 = new LiquidityManagerV4(ADDRESS_PROVIDER);
        provider.setAddress("LiquidityManagerV4", address(managerV4));

        SwapRouter router = new SwapRouter(UNIVERSAL_ROUTER_V4);
        provider.setAddress("SwapRouter", address(router));

        LpAccounts accounts = new LpAccounts(ADDRESS_PROVIDER);
        provider.setAddress("LpAccounts", address(accounts));
        roles.allowContract(address(accounts), "LpAccounts");

        LiquidityOrchestrator orchestrator = new LiquidityOrchestrator(ADDRESS_PROVIDER);
        provider.setAddress("LiquidityOrchestrator", address(orchestrator));
        roles.allowContract(address(orchestrator), "LiquidityOrchestrator");

        vm.stopBroadcast();

        console.log("LiquidityManagerV3", address(managerV3));
        console.log("LiquidityManagerV4", address(managerV4));
        console.log("SwapRouter", address(router));
        console.log("LpAccounts", address(accounts));
        console.log("LiquidityOrchestrator", address(orchestrator));
    }

    function _ensure(IProvider provider, string memory name, address fallbackAddr) internal {
        try provider.getAddress(name) returns (address current) {
            if (current == address(0)) provider.setAddress(name, fallbackAddr);
        } catch {
            provider.setAddress(name, fallbackAddr);
        }
    }

    function _privateKey() internal view returns (uint256) {
        try vm.envUint("ADMIN1_PRIVATE_KEY") returns (uint256 key) {
            return key;
        } catch {}
        try vm.envUint("PRIVATE_KEY") returns (uint256 key) {
            return key;
        } catch {}
        revert("ADMIN1_PRIVATE_KEY o PRIVATE_KEY required");
    }

    error WrongChain();
}

interface IProvider {
    function getAddress(string calldata name) external view returns (address);
    function setAddress(string calldata name, address addr) external;
}

interface IRoles {
    function allowContract(address account, string calldata name) external;
}
