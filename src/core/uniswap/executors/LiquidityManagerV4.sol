// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPermit2} from "../../../interfaces/uniswap/IPermit2.sol";
import {IPositionManagerV4} from "../../../interfaces/uniswap/IPositionManagerV4.sol";
import {ISendraAddressProvider} from "../../../interfaces/iSendraCore/ISendraAddressProvider.sol";
import {UniswapLib} from "../../../lib/uniswap/Uniswap.lib.sol";
import {LiquidityAmounts} from "../../../lib/uniswap/LiquidityAmounts.sol";
import {FullMath} from "../../../lib/uniswap/FullMath.sol";
import {IPoolManager} from "@uniswap/v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/interfaces/IHooks.sol";
import {StateLibrary} from "@uniswap/v4-core/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/libraries/TickMath.sol";
import {PoolKey} from "@uniswap/v4-core/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/types/Currency.sol";

/// @title LiquidityManagerV4
/// @notice Mints and exits Uniswap v4 positions through PositionManager.
///         The Sendra position type is still written by LiquidityOrchestrator.
contract LiquidityManagerV4 {
    using SafeERC20 for IERC20;

    uint8 internal constant MINT_POSITION = 0x02;
    uint8 internal constant DECREASE_LIQUIDITY = 0x01;
    uint8 internal constant BURN_POSITION = 0x03;
    uint8 internal constant SETTLE_PAIR = 0x0d;
    uint8 internal constant TAKE_PAIR = 0x11;
    uint8 internal constant SWEEP = 0x14;

    IPermit2 internal constant PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    ISendraAddressProvider public immutable addressProvider;
    IPositionManagerV4 public immutable positionManager;
    IPoolManager public immutable poolManager;

    constructor(address _addressProvider) {
        addressProvider = ISendraAddressProvider(_addressProvider);
        positionManager = IPositionManagerV4(addressProvider.getAddress("UniswapV4PositionManager"));
        poolManager = IPoolManager(addressProvider.getAddress("UniswapV4PoolManager"));
    }

    modifier onlyOrchestrator() {
        if (msg.sender != addressProvider.getAddress("LiquidityOrchestrator")) revert SenderNotAllowed();
        _;
    }

    function mint(UniswapLib.ProvideLiquidityInput calldata input, address recipient)
        external
        onlyOrchestrator
        returns (UniswapLib.MintOut memory result)
    {
        if (recipient == address(0)) revert ZeroAddress();
        PoolKey memory key = _key(input.token0, input.token1, input.fee, input.tickSpacing, input.hooks);
        PoolId poolId = key.toId();
        (result.sqrtPrice,,,) = StateLibrary.getSlot0(poolManager, poolId);
        if (result.sqrtPrice == 0) revert PoolNotInitialized();

        uint256 use0 = _usable(input.token0, input.amount0);
        uint256 use1 = _usable(input.token1, input.amount1);
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            result.sqrtPrice,
            TickMath.getSqrtPriceAtTick(input.tickLower),
            TickMath.getSqrtPriceAtTick(input.tickUpper),
            use0,
            use1
        );
        if (liquidity == 0) revert ZeroLiquidity();

        _permit(input.token0, use0);
        _permit(input.token1, use1);

        result.tokenId = positionManager.nextTokenId();
        uint256 before0 = IERC20(input.token0).balanceOf(address(this));
        uint256 before1 = IERC20(input.token1).balanceOf(address(this));

        bytes memory actions = abi.encodePacked(MINT_POSITION, SETTLE_PAIR, SWEEP, SWEEP);
        bytes[] memory params = new bytes[](4);
        params[0] = abi.encode(
            key,
            input.tickLower,
            input.tickUpper,
            uint256(liquidity),
            _asUint128(use0),
            _asUint128(use1),
            recipient,
            bytes("")
        );
        params[1] = abi.encode(key.currency0, key.currency1);
        params[2] = abi.encode(key.currency0, address(this));
        params[3] = abi.encode(key.currency1, address(this));
        positionManager.modifyLiquidities(abi.encode(actions, params), block.timestamp + 60);

        result.deposited0 = _spent(input.token0, before0);
        result.deposited1 = _spent(input.token1, before1);
        result.left0 = _sweep(input.token0);
        result.left1 = _sweep(input.token1);
        result.pool = address(poolManager);
        result.poolId = PoolId.unwrap(poolId);
    }

    /// @notice Fees only. Decreasing by zero credits accrued fees and leaves the position in range.
    function collect(uint256 tokenId, PoolKey calldata key, address recipient)
        external
        onlyOrchestrator
        returns (uint256 amount0, uint256 amount1)
    {
        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);
        uint256 before0 = IERC20(token0).balanceOf(recipient);
        uint256 before1 = IERC20(token1).balanceOf(recipient);

        bytes memory actions = abi.encodePacked(DECREASE_LIQUIDITY, TAKE_PAIR);
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(tokenId, uint256(0), uint128(0), uint128(0), bytes(""));
        params[1] = abi.encode(key.currency0, key.currency1, recipient);
        positionManager.modifyLiquidities(abi.encode(actions, params), block.timestamp + 60);

        amount0 = IERC20(token0).balanceOf(recipient) - before0;
        amount1 = IERC20(token1).balanceOf(recipient) - before1;
    }

    /// @notice Burns the NFT and sends principal plus fees to `recipient`.
    function exit(uint256 tokenId, PoolKey calldata key, int24 tickLower, int24 tickUpper, address recipient)
        external
        onlyOrchestrator
        returns (UniswapLib.ExitOut memory result)
    {
        uint128 liquidity = positionManager.getPositionLiquidity(tokenId);
        if (liquidity == 0) revert NothingToExit();

        PoolId poolId = key.toId();
        (result.sqrtPrice,,,) = StateLibrary.getSlot0(poolManager, poolId);
        (uint256 expect0, uint256 expect1) = LiquidityAmounts.getAmountsForLiquidity(
            result.sqrtPrice,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidity
        );
        (uint256 owed0, uint256 owed1) = _feesOwed(key, tickLower, tickUpper, tokenId);

        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);
        uint256 before0 = IERC20(token0).balanceOf(recipient);
        uint256 before1 = IERC20(token1).balanceOf(recipient);

        bytes memory actions = abi.encodePacked(BURN_POSITION, TAKE_PAIR);
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(tokenId, _asUint128((expect0 * 99) / 100), _asUint128((expect1 * 99) / 100), bytes(""));
        params[1] = abi.encode(key.currency0, key.currency1, recipient);
        positionManager.modifyLiquidities(abi.encode(actions, params), block.timestamp + 60);

        uint256 got0 = IERC20(token0).balanceOf(recipient) - before0;
        uint256 got1 = IERC20(token1).balanceOf(recipient) - before1;
        result.fee0 = owed0 > got0 ? got0 : owed0;
        result.fee1 = owed1 > got1 ? got1 : owed1;
        result.principal0 = got0 - result.fee0;
        result.principal1 = got1 - result.fee1;
    }

    function _feesOwed(PoolKey memory key, int24 tickLower, int24 tickUpper, uint256 tokenId)
        internal
        view
        returns (uint256 fee0, uint256 fee1)
    {
        PoolId poolId = key.toId();
        (uint128 liquidity, uint256 last0, uint256 last1) = StateLibrary.getPositionInfo(
            poolManager, poolId, address(positionManager), tickLower, tickUpper, bytes32(tokenId)
        );
        if (liquidity == 0) return (0, 0);
        (uint256 inside0, uint256 inside1) = StateLibrary.getFeeGrowthInside(poolManager, poolId, tickLower, tickUpper);
        unchecked {
            fee0 = FullMath.mulDiv(liquidity, inside0 - last0, 1 << 128);
            fee1 = FullMath.mulDiv(liquidity, inside1 - last1, 1 << 128);
        }
    }

    function _key(address token0, address token1, uint24 fee, int24 tickSpacing, address hooks)
        internal
        pure
        returns (PoolKey memory)
    {
        return PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(hooks)
        });
    }

    function _permit(address token, uint256 amount) internal {
        if (amount == 0) return;
        IERC20(token).forceApprove(address(PERMIT2), amount);
        PERMIT2.approve(token, address(positionManager), _asUint160(amount), uint48(block.timestamp + 1 hours));
    }

    function _usable(address token, uint256 wanted) internal view returns (uint256) {
        uint256 balance = IERC20(token).balanceOf(address(this));
        return balance < wanted ? balance : wanted;
    }

    function _spent(address token, uint256 beforeBalance) internal view returns (uint256) {
        uint256 afterBalance = IERC20(token).balanceOf(address(this));
        return beforeBalance > afterBalance ? beforeBalance - afterBalance : 0;
    }

    function _sweep(address token) internal returns (uint256 amount) {
        amount = IERC20(token).balanceOf(address(this));
        if (amount > 0) IERC20(token).safeTransfer(msg.sender, amount);
    }

    function _asUint128(uint256 amount) internal pure returns (uint128) {
        if (amount > type(uint128).max) revert AmountTooLarge();
        return uint128(amount);
    }

    function _asUint160(uint256 amount) internal pure returns (uint160) {
        if (amount > type(uint160).max) revert AmountTooLarge();
        return uint160(amount);
    }

    error SenderNotAllowed();
    error ZeroAddress();
    error ZeroLiquidity();
    error PoolNotInitialized();
    error NothingToExit();
    error AmountTooLarge();
}
