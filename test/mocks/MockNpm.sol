// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {MockERC20} from "./MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockV3Pool {
    function getPool(address, address, uint24) external view returns (address) {
        return address(this);
    }

    function slot0() external pure returns (uint160, int24, uint16, uint16, uint16, uint8, bool) {
        return (79228162514264337593543950336, 0, 0, 0, 0, 0, true);
    }
}

contract MockNpm {
    uint256 public takeBps = 10_000;
    uint256 public nextId = 1;

    mapping(uint256 => address) public token0Of;
    mapping(uint256 => address) public token1Of;
    mapping(uint256 => uint256) public deposited0;
    mapping(uint256 => uint256) public deposited1;
    mapping(uint256 => uint256) public fees0;
    mapping(uint256 => uint256) public fees1;
    mapping(uint256 => uint256) public principal0;
    mapping(uint256 => uint256) public principal1;
    mapping(uint256 => uint128) public liquidityOf;

    function setTakeBps(uint256 next) external {
        takeBps = next;
    }

    function setApprovalForAll(address, bool) external {}

    function accrue(uint256 tokenId, uint256 fee0, uint256 fee1) external {
        fees0[tokenId] = fee0;
        fees1[tokenId] = fee1;
    }

    function mint(IMint.MintParams calldata params)
        external
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        amount0 = params.amount0Desired * takeBps / 10_000;
        amount1 = params.amount1Desired * takeBps / 10_000;
        if (amount0 > 0) IERC20(params.token0).transferFrom(msg.sender, address(this), amount0);
        if (amount1 > 0) IERC20(params.token1).transferFrom(msg.sender, address(this), amount1);
        tokenId = nextId++;
        token0Of[tokenId] = params.token0;
        token1Of[tokenId] = params.token1;
        deposited0[tokenId] = amount0;
        deposited1[tokenId] = amount1;
        liquidityOf[tokenId] = 1;
        liquidity = 1;
    }

    function decreaseLiquidity(IMint.DecreaseLiquidityParams calldata params) external returns (uint256, uint256) {
        principal0[params.tokenId] = deposited0[params.tokenId];
        principal1[params.tokenId] = deposited1[params.tokenId];
        liquidityOf[params.tokenId] = 0;
        return (principal0[params.tokenId], principal1[params.tokenId]);
    }

    function collect(IMint.CollectParams calldata params) external returns (uint256 amount0, uint256 amount1) {
        uint256 id = params.tokenId;
        amount0 = fees0[id] + principal0[id];
        amount1 = fees1[id] + principal1[id];
        uint256 fee0 = fees0[id];
        uint256 fee1 = fees1[id];
        uint256 owed0 = principal0[id];
        uint256 owed1 = principal1[id];
        fees0[id] = 0;
        fees1[id] = 0;
        principal0[id] = 0;
        principal1[id] = 0;
        if (owed0 > 0) IERC20(token0Of[id]).transfer(params.recipient, owed0);
        if (owed1 > 0) IERC20(token1Of[id]).transfer(params.recipient, owed1);
        if (fee0 > 0) MockERC20(token0Of[id]).mint(params.recipient, fee0);
        if (fee1 > 0) MockERC20(token1Of[id]).mint(params.recipient, fee1);
    }

    function burn(uint256 tokenId) external view {
        require(liquidityOf[tokenId] == 0, "liquidity");
    }

    function positions(uint256 tokenId)
        external
        view
        returns (uint96, address, address, address, uint24, int24, int24, uint128, uint256, uint256, uint128, uint128)
    {
        return (0, address(0), token0Of[tokenId], token1Of[tokenId], 3000, -600, 600, liquidityOf[tokenId], 0, 0, 0, 0);
    }
}

interface IMint {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }
}
