// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface ISendraAddressProvider {
    function getAddress(string calldata contractName) external view returns (address);

    error AddressNotFound(string contractName);
}
