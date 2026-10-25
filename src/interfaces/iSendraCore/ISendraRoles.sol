// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface ISendraRoles {
    function checkAdmin(address account) external view returns (bool);

    function isProtocolContract(address account) external view returns (bool);

    function allowContract(address account, string calldata name) external;
}
