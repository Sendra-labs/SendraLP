// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ISendraAddressProvider} from "../interfaces/iSendraCore/ISendraAddressProvider.sol";
import {LpCell} from "../execution/LpCell.sol";

interface IAccountsManager {
    function accountByOwner(address owner) external view returns (address);
}

interface IAccountAccess {
    function setIsProtocolAccount(address account) external;
}

/// @title LpAccounts
/// @notice Resolves the LP account of a user.
///         The spot account from AccountsManager is that account when it implements `lpEnabled`.
///         A dedicated cell is only deployed for an owner whose spot account cannot learn LP.
///         Aave keeps its own accounts and is not resolved here.
contract LpAccounts {
    ISendraAddressProvider public immutable addressProvider;
    mapping(address => address) public cellByOwner;

    event CellOpened(address indexed owner, address indexed cell);

    constructor(address _addressProvider) {
        addressProvider = ISendraAddressProvider(_addressProvider);
    }

    /// @notice Spot account when it can hold LP. Otherwise the cell opened for this owner.
    function cellFor(address user) public view returns (address cell) {
        cell = _spot(user);
        if (cell != address(0)) return cell;
        return cellByOwner[user];
    }

    function open() external returns (address cell) {
        cell = cellFor(msg.sender);
        if (cell == address(0)) cell = address(new LpCell(address(addressProvider), msg.sender));
        if (cellByOwner[msg.sender] == cell) return cell;

        cellByOwner[msg.sender] = cell;
        IAccountAccess(addressProvider.getAddress("AccountAccessControl")).setIsProtocolAccount(cell);
        emit CellOpened(msg.sender, cell);
    }

    function _spot(address user) internal view returns (address spot) {
        spot = IAccountsManager(addressProvider.getAddress("AccountsManager")).accountByOwner(user);
        if (!_lpEnabled(spot)) return address(0);
        (bool ok, bytes memory data) = spot.staticcall(abi.encodeWithSignature("owner()"));
        if (!ok || data.length != 32 || abi.decode(data, (address)) != user) return address(0);
    }

    function _lpEnabled(address spot) internal view returns (bool) {
        if (spot == address(0) || spot.code.length == 0) return false;
        (bool ok, bytes memory data) = spot.staticcall(abi.encodeWithSignature("lpEnabled()"));
        return ok && data.length == 32 && abi.decode(data, (bool));
    }
}
