// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPermit2} from "../../src/interfaces/uniswap/IPermit2.sol";
import {PoolKey} from "@uniswap/v4-core/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/types/Currency.sol";

contract MockPermit2 is IPermit2 {
    function approve(address, address, uint160, uint48) external {}

    function transferFrom(address from, address to, uint160 amount, address token) external {
        if (amount > 0) IERC20(token).transferFrom(from, to, amount);
    }
}

contract MockPoolManager {
    bytes32 internal constant SQRT = bytes32(uint256(79228162514264337593543950336));

    function extsload(bytes32) external pure returns (bytes32) {
        return SQRT;
    }

    function extsload(bytes32, uint256 nSlots) external pure returns (bytes32[] memory values) {
        values = new bytes32[](nSlots);
    }

    function extsload(bytes32[] calldata slots) external pure returns (bytes32[] memory values) {
        values = new bytes32[](slots.length);
    }
}

contract MockV4PositionManager {
    IPermit2 internal constant PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    uint256 public nextTokenId = 1;
    uint256 public pullBps = 10_000;

    struct Pos {
        address token0;
        address token1;
        uint256 amount0;
        uint256 amount1;
        bool alive;
    }

    mapping(uint256 => Pos) public positions;

    function setPullBps(uint256 next) external {
        pullBps = next;
    }

    function setApprovalForAll(address, bool) external {}

    function getPositionLiquidity(uint256 tokenId) external view returns (uint128) {
        return positions[tokenId].alive ? 1 : 0;
    }

    function modifyLiquidities(bytes calldata unlockData, uint256) external {
        (bytes memory actions, bytes[] memory params) = abi.decode(unlockData, (bytes, bytes[]));
        uint8 kind = uint8(actions[0]);
        if (kind == 0x02) {
            if (actions.length != 4 || uint8(actions[1]) != 0x0d || uint8(actions[2]) != 0x14 || uint8(actions[3]) != 0x14) {
                revert BadActions();
            }
            (
                PoolKey memory key,
                ,
                ,
                ,
                uint128 amount0Max,
                uint128 amount1Max,
                ,
            ) = abi.decode(params[0], (PoolKey, int24, int24, uint256, uint128, uint128, address, bytes));
            uint256 id = nextTokenId++;
            uint256 pull0 = uint256(amount0Max) * pullBps / 10_000;
            uint256 pull1 = uint256(amount1Max) * pullBps / 10_000;
            address token0 = Currency.unwrap(key.currency0);
            address token1 = Currency.unwrap(key.currency1);
            if (pull0 > 0) PERMIT2.transferFrom(msg.sender, address(this), uint160(pull0), token0);
            if (pull1 > 0) PERMIT2.transferFrom(msg.sender, address(this), uint160(pull1), token1);
            positions[id] = Pos(token0, token1, pull0, pull1, true);
            return;
        }
        if (kind == 0x03) {
            if (actions.length != 2 || uint8(actions[1]) != 0x11) revert BadActions();
            (uint256 tokenId,,,) = abi.decode(params[0], (uint256, uint128, uint128, bytes));
            (,, address recipient) = abi.decode(params[1], (Currency, Currency, address));
            Pos memory pos = positions[tokenId];
            if (pos.amount0 > 0) IERC20(pos.token0).transfer(recipient, pos.amount0);
            if (pos.amount1 > 0) IERC20(pos.token1).transfer(recipient, pos.amount1);
            positions[tokenId].alive = false;
            positions[tokenId].amount0 = 0;
            positions[tokenId].amount1 = 0;
            return;
        }
        if (kind == 0x01) {
            if (actions.length != 2 || uint8(actions[1]) != 0x11) revert BadActions();
            return;
        }
        revert BadActions();
    }

    error BadActions();
}
