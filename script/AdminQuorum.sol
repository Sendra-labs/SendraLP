// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Script } from "forge-std/Script.sol";

interface IQuorumProvider {
    function getAddress(string calldata name) external view returns (address);
    function proposeAddress(string calldata name, address addr) external;
}

interface IQuorumRoles {
    function allowContract(address account, string calldata name) external;
}

abstract contract AdminQuorum is Script {
    function _keys() internal view returns (uint256[3] memory keys) {
        keys[0] = vm.envUint("HOT_ADMIN1_PRIVATE_KEY");
        keys[1] = vm.envUint("HOT_ADMIN2_PRIVATE_KEY");
        keys[2] = vm.envUint("HOT_ADMIN3_PRIVATE_KEY");
    }

    function _provider() internal view returns (IQuorumProvider) {
        return IQuorumProvider(vm.envAddress("ADDRESS_PROVIDER"));
    }

    function _propose(IQuorumProvider provider, string memory name, address addr) internal {
        uint256[3] memory keys = _keys();
        for (uint256 i = 0; i < 3; i++) {
            vm.startBroadcast(keys[i]);
            provider.proposeAddress(name, addr);
            vm.stopBroadcast();
        }
    }

    function _register(IQuorumProvider provider, IQuorumRoles roles, string memory name, address addr) internal {
        uint256[3] memory keys = _keys();
        for (uint256 i = 0; i < 3; i++) {
            vm.startBroadcast(keys[i]);
            provider.proposeAddress(name, addr);
            roles.allowContract(addr, name);
            vm.stopBroadcast();
        }
    }

    function _ensure(IQuorumProvider provider, string memory name, address addr) internal {
        try provider.getAddress(name) returns (address current) {
            if (current == addr) return;
        } catch {}
        _propose(provider, name, addr);
    }
}
