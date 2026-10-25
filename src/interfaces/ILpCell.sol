// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface ILpCell {
    function owner() external view returns (address);

    function lpEnabled() external view returns (bool);

    function push(address token, address to, uint256 amount) external;
}
