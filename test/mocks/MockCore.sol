// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SendraLib} from "../../src/lib/Sendra.lib.sol";
import {ISendraAddressProvider} from "../../src/interfaces/iSendraCore/ISendraAddressProvider.sol";
import {ISendraStorage} from "../../src/interfaces/iSendraCore/ISendraStorage.sol";
import {UniswapLib} from "../../src/lib/uniswap/Uniswap.lib.sol";

contract MockProvider is ISendraAddressProvider {
    mapping(string => address) public addr;

    function set(string calldata name, address who) external {
        addr[name] = who;
    }

    function getAddress(string calldata name) external view returns (address) {
        address who = addr[name];
        if (who == address(0)) revert AddressNotFound(name);
        return who;
    }
}

contract MockRoles {
    function checkAdmin(address) external pure returns (bool) {
        return true;
    }

    function isProtocolContract(address) external pure returns (bool) {
        return true;
    }

    function allowContract(address, string calldata) external {}
}

contract MockAccountsManager {
    mapping(address => address) public accountByOwner;

    function setAccount(address owner, address account) external {
        accountByOwner[owner] = account;
    }
}

contract MockAccountAccess {
    function setIsProtocolAccount(address) external {}
}

contract MockStorage is ISendraStorage {
    mapping(address => mapping(uint256 => SendraLib.Position)) public book;
    mapping(address => uint256) public total;
    mapping(address => uint256) public activeOf;
    uint256 public globalPulses;
    uint256 public specificPulses;
    address public lastUser;

    function add(address user, uint128 positionType, bytes[] memory data) external returns (uint256 id) {
        id = total[user] + 1;
        book[user][id] = SendraLib.Position({
            positionType: positionType,
            id: id,
            pnl: 0,
            isActive: true,
            positionData: data
        });
        total[user] = id;
        activeOf[user] += 1;
    }

    function getUser(address user) external view returns (SendraLib.UserInfoRead memory info) {
        info.totalPositions = total[user];
        info.activePositions = activeOf[user];
    }

    function getUserPositionById(address user, uint256 positionId) external view returns (SendraLib.Position memory) {
        return book[user][positionId];
    }

    function updateUserFullPosition(address user, uint256 positionId, SendraLib.Position memory position) external {
        book[user][positionId] = position;
    }

    function decreaseGlobalPositionActivePositions(address user) external {
        activeOf[user] -= 1;
    }

    function applyGlobalPulseDeltas(address user, uint8[] calldata, int256[] calldata) external {
        globalPulses += 1;
        lastUser = user;
    }

    function applySpecificPulseDeltas(address user, uint64, uint8[] calldata, int256[] calldata) external {
        specificPulses += 1;
        lastUser = user;
    }

    function applyMetricDelta(address, uint64, uint256, int256) external {}

    function getUniqueGlobalAccumulator(uint8, address) external pure returns (int256) {
        return 0;
    }
}

contract MockInitializer {
    MockStorage public store;

    constructor(MockStorage store_) {
        store = store_;
    }

    function initializePosition(bytes[] memory data, uint128 positionType, address user) external {
        store.add(user, positionType, data);
    }
}

contract MockSwapRouter {
    function executeSwap(UniswapLib.SwapInput memory input) external {
        require(input.amountIn0 > 0, "amount");
        MockMint(input.tokenOut).mint(input.to, input.amountIn0);
    }
}

interface MockMint {
    function mint(address to, uint256 amount) external;
}
