// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISendraAddressProvider} from "../../../interfaces/iSendraCore/ISendraAddressProvider.sol";
import {ISendraStorage} from "../../../interfaces/iSendraCore/ISendraStorage.sol";
import {IPositionInitializer} from "../../../interfaces/iSendraCore/IPositionInitializer.sol";
import {ISwapRouter} from "../../../interfaces/uniswap/ISwapRouter.sol";
import {ILpCell} from "../../../interfaces/ILpCell.sol";
import {LpAccounts} from "../../../storage/LpAccounts.sol";
import {LiquidityManagerV3} from "./LiquidityManagerV3.sol";
import {LiquidityManagerV4} from "./LiquidityManagerV4.sol";
import {SendraLib} from "../../../lib/Sendra.lib.sol";
import {UniswapLib} from "../../../lib/uniswap/Uniswap.lib.sol";
import {LpData} from "../../../lib/uniswap/LpData.sol";
import {LpPulse} from "../../../lib/uniswap/LpPulse.lib.sol";
import {SwapScale} from "../../../lib/uniswap/SwapScale.lib.sol";
import {IHooks} from "@uniswap/v4-core/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/types/Currency.sol";

/// @title LiquidityOrchestrator
/// @notice One entry for Uniswap v3 and v4. Both write Sendra position type 2.
///         v3 and v4 differ only in the manager. Partial close removes the LP and
///         holds the tokens; the Sendra position stays open until those tokens are sold.
contract LiquidityOrchestrator is ReentrancyGuard {
    using SafeERC20 for IERC20;

    ISendraAddressProvider public immutable addressProvider;
    LiquidityManagerV3 public immutable managerV3;
    LiquidityManagerV4 public immutable managerV4;
    ISwapRouter public immutable swapRouter;
    ISendraStorage public immutable sendraStorage;
    IPositionInitializer public immutable initializer;
    LpAccounts public immutable lpAccounts;

    event LiquidityProvided(address indexed user, uint256 indexed positionId, uint8 protocol, uint256 tokenId);
    event LiquidityUnwound(address indexed user, uint256 indexed positionId, uint256 held0, uint256 held1);
    event LiquiditySold(address indexed user, uint256 indexed positionId, uint256 baseOut, int256 pnl);
    event FeesCollected(address indexed user, uint256 indexed positionId, uint256 baseOut);

    struct OpenLp {
        address token0;
        address token1;
        uint256 openDate;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        address recipient;
        uint256 tokenId;
        uint8 protocol;
        int24 tickSpacing;
        address hooks;
        uint8 phase;
        uint256 held0;
        uint256 held1;
        uint256 fee0;
        uint256 fee1;
        bytes32 poolId;
        address pool;
        address base;
        uint160 sqrtFinal;
    }

    constructor(address _addressProvider) {
        addressProvider = ISendraAddressProvider(_addressProvider);
        managerV3 = LiquidityManagerV3(addressProvider.getAddress("LiquidityManager"));
        managerV4 = LiquidityManagerV4(addressProvider.getAddress("LiquidityManagerV4"));
        swapRouter = ISwapRouter(addressProvider.getAddress("SwapRouter"));
        sendraStorage = ISendraStorage(addressProvider.getAddress("SendraStorage"));
        initializer = IPositionInitializer(addressProvider.getAddress("PositionInitializer"));
        lpAccounts = LpAccounts(addressProvider.getAddress("LpAccounts"));
    }

    function provideLiquidity(UniswapLib.ExecuteProvideLiquidityInput calldata input)
        external
        nonReentrant
        returns (uint256 positionId)
    {
        UniswapLib.ProvideLiquidityInput memory p = input.provideLiquidityInput;
        _onlyCell(p.user);
        if (p.token0 == address(0) || p.token1 == address(0)) revert NativeCurrency();
        if (p.token0 >= p.token1) revert TokenOrder();
        if (p.tickLower >= p.tickUpper) revert BadTicks();
        if (input.swapInput0.tokenIn != input.swapInput1.tokenIn) revert BaseMismatch();

        address base = input.swapInput0.tokenIn;
        uint256 totalIn = input.swapInput0.amountIn0 + input.swapInput1.amountIn0;
        if (totalIn == 0) revert ZeroAmount();

        address sink = _sink(p.protocol, p.tickLower, p.tickUpper, p.tickSpacing);
        _fund(input.swapInput0, sink);
        _fund(input.swapInput1, sink);

        UniswapLib.MintOut memory minted = p.protocol == UniswapLib.Protocol.UniswapV3
            ? managerV3.mint(p, msg.sender)
            : managerV4.mint(p, msg.sender);
        if (minted.deposited0 == 0 && minted.deposited1 == 0) revert ZeroLiquidity();

        uint256 refund = _toBase(p.token0, minted.left0, base, input.invertedSwapInput0)
            + _toBase(p.token1, minted.left1, base, input.invertedSwapInput1);
        if (refund > totalIn) revert RefundTooLarge();
        if (refund > 0) {
            if (IERC20(base).balanceOf(address(this)) < refund) revert ShortBase();
            IERC20(base).safeTransfer(p.user, refund);
        }

        positionId = _recordOpen(p, minted, base, totalIn - refund);
        LpPulse.onOpen(sendraStorage, p.user, totalIn - refund);
        emit LiquidityProvided(p.user, positionId, uint8(p.protocol), minted.tokenId);
    }

    function partialClose(UniswapLib.PartialCloseInput calldata input) external nonReentrant {
        _onlyCell(input.user);
        SendraLib.Position memory position = sendraStorage.getUserPositionById(input.user, input.positionId);
        OpenLp memory s = _loadLive(position, input.uniId);
        UniswapLib.ExitOut memory out = _exit(s, msg.sender);

        uint256 held0 = out.principal0 + out.fee0;
        uint256 held1 = out.principal1 + out.fee1;
        position.positionData[LpData.HELD0] = abi.encode(held0);
        position.positionData[LpData.HELD1] = abi.encode(held1);
        position.positionData[LpData.FEE0] = abi.encode(out.fee0);
        position.positionData[LpData.FEE1] = abi.encode(out.fee1);
        position.positionData[LpData.PHASE] = abi.encode(uint8(LpData.PHASE_HOLDING));
        position.positionData[LpData.SQRT_FINAL] = abi.encode(out.sqrtPrice);
        sendraStorage.updateUserFullPosition(input.user, input.positionId, position);
        emit LiquidityUnwound(input.user, input.positionId, held0, held1);
    }

    function sellHeld(UniswapLib.SellHeldInput calldata input) external nonReentrant returns (uint256 baseOut) {
        _onlyCell(input.user);
        SendraLib.Position memory position = sendraStorage.getUserPositionById(input.user, input.positionId);
        OpenLp memory s = _loadOwned(position);
        if (s.phase != LpData.PHASE_HOLDING) revert WrongPhase();
        _sameBase(input.swapInput0, input.swapInput1, s.base);

        if (s.held0 > 0) ILpCell(msg.sender).push(s.token0, address(this), s.held0);
        if (s.held1 > 0) ILpCell(msg.sender).push(s.token1, address(this), s.held1);

        uint256 feesUsdc = _toBase(s.token0, s.fee0, s.base, input.swapInput0)
            + _toBase(s.token1, s.fee1, s.base, input.swapInput1);
        uint256 principalUsdc = _toBase(s.token0, s.held0 - s.fee0, s.base, input.swapInput0)
            + _toBase(s.token1, s.held1 - s.fee1, s.base, input.swapInput1);
        baseOut = feesUsdc + principalUsdc;
        _pay(s.base, baseOut, input.user);
        int256 pnl = _finalize(position, input.user, input.positionId, feesUsdc, baseOut, s.sqrtFinal, s.openDate);
        emit LiquiditySold(input.user, input.positionId, baseOut, pnl);
    }

    function withdrawLiquidityAndCollectFees(UniswapLib.ExecuteWithdrawLiquidityAndCollectFees calldata input)
        external
        nonReentrant
        returns (uint256 baseOut)
    {
        _onlyCell(input.withdrawInput.user);
        SendraLib.Position memory position =
            sendraStorage.getUserPositionById(input.withdrawInput.user, input.withdrawInput.positionId);
        OpenLp memory s = _loadLive(position, input.withdrawInput.uniId);
        _sameBase(input.swapInput0, input.swapInput1, s.base);

        UniswapLib.ExitOut memory out = _exit(s, address(this));
        uint256 feesUsdc = _toBase(s.token0, out.fee0, s.base, input.swapInput0)
            + _toBase(s.token1, out.fee1, s.base, input.swapInput1);
        uint256 principalUsdc = _toBase(s.token0, out.principal0, s.base, input.swapInput0)
            + _toBase(s.token1, out.principal1, s.base, input.swapInput1);
        baseOut = feesUsdc + principalUsdc;
        _pay(s.base, baseOut, input.withdrawInput.user);
        int256 pnl = _finalize(position, input.withdrawInput.user, input.withdrawInput.positionId, feesUsdc, baseOut, out.sqrtPrice, s.openDate);
        emit LiquiditySold(input.withdrawInput.user, input.withdrawInput.positionId, baseOut, pnl);
    }

    function collectFeesOnly(UniswapLib.ExecuteCollectFeesOnly calldata input)
        external
        nonReentrant
        returns (uint256 baseOut)
    {
        _onlyCell(input.collectInput.user);
        SendraLib.Position memory position =
            sendraStorage.getUserPositionById(input.collectInput.user, input.collectInput.positionId);
        OpenLp memory s = _loadLive(position, input.collectInput.uniId);
        _sameBase(input.swapInput0, input.swapInput1, s.base);

        (uint256 amount0, uint256 amount1) = _collect(s, address(this));
        baseOut = _toBase(s.token0, amount0, s.base, input.swapInput0)
            + _toBase(s.token1, amount1, s.base, input.swapInput1);
        _pay(s.base, baseOut, input.collectInput.user);

        uint256 prior = abi.decode(position.positionData[LpData.FEES_USD], (uint256));
        position.positionData[LpData.FEES_USD] = abi.encode(prior + baseOut);
        sendraStorage.updateUserFullPosition(input.collectInput.user, input.collectInput.positionId, position);
        sendraStorage.applyMetricDelta(input.collectInput.user, uint64(LpData.POSITION_TYPE), 0, int256(baseOut));
        emit FeesCollected(input.collectInput.user, input.collectInput.positionId, baseOut);
    }

    function invertSwapInput(UniswapLib.SwapInput memory input, uint256 amount)
        external
        view
        returns (UniswapLib.SwapInput memory)
    {
        return SwapScale.invert(input, amount, address(this));
    }

    function _recordOpen(
        UniswapLib.ProvideLiquidityInput memory p,
        UniswapLib.MintOut memory minted,
        address base,
        uint256 initial
    ) internal returns (uint256 positionId) {
        bytes[] memory data = new bytes[](LpData.LEN);
        data[LpData.TOKEN0] = abi.encode(p.token0);
        data[LpData.TOKEN1] = abi.encode(p.token1);
        data[LpData.OPENED] = abi.encode(block.timestamp);
        data[LpData.FEE] = abi.encode(p.fee);
        data[LpData.TICK_LOWER] = abi.encode(p.tickLower);
        data[LpData.TICK_UPPER] = abi.encode(p.tickUpper);
        data[LpData.AMOUNT0] = abi.encode(minted.deposited0);
        data[LpData.AMOUNT1] = abi.encode(minted.deposited1);
        data[LpData.RECIPIENT] = abi.encode(msg.sender);
        data[LpData.TOKEN_ID] = abi.encode(minted.tokenId);
        data[LpData.SQRT_OPEN] = abi.encode(minted.sqrtPrice);
        data[LpData.POOL] = abi.encode(minted.pool);
        data[LpData.FINAL_USD] = abi.encode(uint256(0));
        data[LpData.SQRT_FINAL] = abi.encode(uint160(0));
        data[LpData.FEES_USD] = abi.encode(uint256(0));
        data[LpData.INITIAL_USD] = abi.encode(initial);
        data[LpData.CLOSED] = abi.encode(uint256(0));
        data[LpData.CHAIN_ID] = abi.encode(block.chainid);
        data[LpData.PROTOCOL] = abi.encode(uint8(p.protocol));
        data[LpData.TICK_SPACING] = abi.encode(p.tickSpacing);
        data[LpData.HOOKS] = abi.encode(p.hooks);
        data[LpData.PHASE] = abi.encode(uint8(LpData.PHASE_LIVE));
        data[LpData.HELD0] = abi.encode(uint256(0));
        data[LpData.HELD1] = abi.encode(uint256(0));
        data[LpData.FEE0] = abi.encode(uint256(0));
        data[LpData.FEE1] = abi.encode(uint256(0));
        data[LpData.POOL_ID] = abi.encode(minted.poolId);
        data[LpData.BASE] = abi.encode(base);

        initializer.initializePosition(data, LpData.POSITION_TYPE, p.user);
        positionId = sendraStorage.getUser(p.user).totalPositions;
    }

    function _finalize(
        SendraLib.Position memory position,
        address user,
        uint256 positionId,
        uint256 feesUsdc,
        uint256 payout,
        uint160 sqrtPrice,
        uint256 openedAt
    ) internal returns (int256 pnl) {
        uint256 initial = abi.decode(position.positionData[LpData.INITIAL_USD], (uint256));
        uint256 priorFees = abi.decode(position.positionData[LpData.FEES_USD], (uint256));
        pnl = int256(payout) - int256(initial);
        position.isActive = false;
        position.pnl = pnl;
        position.positionData[LpData.FINAL_USD] = abi.encode(payout);
        position.positionData[LpData.SQRT_FINAL] = abi.encode(sqrtPrice);
        position.positionData[LpData.FEES_USD] = abi.encode(priorFees + feesUsdc);
        position.positionData[LpData.CLOSED] = abi.encode(block.timestamp);
        position.positionData[LpData.PHASE] = abi.encode(uint8(LpData.PHASE_CLOSED));
        position.positionData[LpData.HELD0] = abi.encode(uint256(0));
        position.positionData[LpData.HELD1] = abi.encode(uint256(0));
        sendraStorage.updateUserFullPosition(user, positionId, position);
        sendraStorage.decreaseGlobalPositionActivePositions(user);
        LpPulse.onClose(sendraStorage, user, pnl, payout, initial, openedAt);
        sendraStorage.applyMetricDelta(user, uint64(LpData.POSITION_TYPE), 0, int256(feesUsdc));
    }

    function _exit(OpenLp memory s, address recipient) internal returns (UniswapLib.ExitOut memory out) {
        if (s.protocol == uint8(UniswapLib.Protocol.UniswapV3)) {
            return managerV3.exit(s.tokenId, s.tickLower, s.tickUpper, s.pool, recipient);
        }
        if (s.protocol == uint8(UniswapLib.Protocol.UniswapV4)) {
            return managerV4.exit(s.tokenId, _key(s), s.tickLower, s.tickUpper, recipient);
        }
        revert UnsupportedProtocol();
    }

    function _collect(OpenLp memory s, address recipient) internal returns (uint256 amount0, uint256 amount1) {
        if (s.protocol == uint8(UniswapLib.Protocol.UniswapV3)) return managerV3.collect(s.tokenId, recipient);
        if (s.protocol == uint8(UniswapLib.Protocol.UniswapV4)) return managerV4.collect(s.tokenId, _key(s), recipient);
        revert UnsupportedProtocol();
    }

    function _key(OpenLp memory s) internal pure returns (PoolKey memory key) {
        key = PoolKey({
            currency0: Currency.wrap(s.token0),
            currency1: Currency.wrap(s.token1),
            fee: s.fee,
            tickSpacing: s.tickSpacing,
            hooks: IHooks(s.hooks)
        });
        if (PoolId.unwrap(key.toId()) != s.poolId) revert PoolMismatch();
    }

    function _fund(UniswapLib.SwapInput calldata swap, address manager) internal {
        if (swap.amountIn0 == 0) return;
        bool needSwap = swap.tokenIn != swap.tokenOut;
        IERC20(swap.tokenIn).safeTransferFrom(msg.sender, needSwap ? address(swapRouter) : manager, swap.amountIn0);
        if (needSwap) {
            UniswapLib.SwapInput memory next = swap;
            next.to = manager;
            swapRouter.executeSwap(next);
        }
    }

    function _toBase(address token, uint256 amount, address base, UniswapLib.SwapInput calldata route)
        internal
        returns (uint256 got)
    {
        if (amount == 0) return 0;
        if (token == base) return amount;
        uint256 before = IERC20(base).balanceOf(address(this));
        IERC20(token).safeTransfer(address(swapRouter), amount);
        swapRouter.executeSwap(SwapScale.scale(route, token, base, amount, address(this)));
        got = IERC20(base).balanceOf(address(this)) - before;
    }

    function _pay(address base, uint256 amount, address user) internal {
        if (amount == 0) return;
        if (IERC20(base).balanceOf(address(this)) < amount) revert ShortBase();
        IERC20(base).safeTransfer(user, amount);
    }

    function _sink(UniswapLib.Protocol protocol, int24 tickLower, int24 tickUpper, int24 tickSpacing)
        internal
        view
        returns (address)
    {
        if (protocol == UniswapLib.Protocol.UniswapV3) return address(managerV3);
        if (protocol == UniswapLib.Protocol.UniswapV4) {
            if (tickSpacing <= 0 || tickLower % tickSpacing != 0 || tickUpper % tickSpacing != 0) revert BadTicks();
            return address(managerV4);
        }
        revert UnsupportedProtocol();
    }

    function _loadLive(SendraLib.Position memory position, uint256 uniId) internal view returns (OpenLp memory s) {
        s = _loadOwned(position);
        if (s.phase != LpData.PHASE_LIVE) revert WrongPhase();
        if (uniId != s.tokenId) revert TokenMismatch();
    }

    function _loadOwned(SendraLib.Position memory position) internal view returns (OpenLp memory s) {
        if (!position.isActive) revert PositionInactive();
        if (position.positionType != LpData.POSITION_TYPE) revert PositionTypeMismatch();
        s = _load(position);
        if (s.recipient != msg.sender) revert NotLpCell();
    }

    function _load(SendraLib.Position memory position) internal pure returns (OpenLp memory s) {
        bytes[] memory data = position.positionData;
        if (data.length < LpData.LEN) revert LegacyPosition();
        s.token0 = abi.decode(data[LpData.TOKEN0], (address));
        s.token1 = abi.decode(data[LpData.TOKEN1], (address));
        s.openDate = abi.decode(data[LpData.OPENED], (uint256));
        s.fee = abi.decode(data[LpData.FEE], (uint24));
        s.tickLower = abi.decode(data[LpData.TICK_LOWER], (int24));
        s.tickUpper = abi.decode(data[LpData.TICK_UPPER], (int24));
        s.recipient = abi.decode(data[LpData.RECIPIENT], (address));
        s.tokenId = abi.decode(data[LpData.TOKEN_ID], (uint256));
        s.protocol = abi.decode(data[LpData.PROTOCOL], (uint8));
        s.tickSpacing = abi.decode(data[LpData.TICK_SPACING], (int24));
        s.hooks = abi.decode(data[LpData.HOOKS], (address));
        s.phase = abi.decode(data[LpData.PHASE], (uint8));
        s.held0 = abi.decode(data[LpData.HELD0], (uint256));
        s.held1 = abi.decode(data[LpData.HELD1], (uint256));
        s.fee0 = abi.decode(data[LpData.FEE0], (uint256));
        s.fee1 = abi.decode(data[LpData.FEE1], (uint256));
        s.poolId = abi.decode(data[LpData.POOL_ID], (bytes32));
        s.pool = abi.decode(data[LpData.POOL], (address));
        s.base = abi.decode(data[LpData.BASE], (address));
        s.sqrtFinal = abi.decode(data[LpData.SQRT_FINAL], (uint160));
    }

    function _onlyCell(address user) internal view {
        if (user == address(0) || msg.sender != lpAccounts.cellFor(user)) revert NotLpCell();
        if (ILpCell(msg.sender).owner() != user) revert NotLpCell();
    }

    function _sameBase(UniswapLib.SwapInput calldata a, UniswapLib.SwapInput calldata b, address expected) internal pure {
        if (a.tokenOut != expected || b.tokenOut != expected) revert BaseMismatch();
    }

    error NotLpCell();
    error TokenOrder();
    error NativeCurrency();
    error BadTicks();
    error BaseMismatch();
    error ZeroAmount();
    error ZeroLiquidity();
    error RefundTooLarge();
    error ShortBase();
    error UnsupportedProtocol();
    error WrongPhase();
    error TokenMismatch();
    error PositionInactive();
    error PositionTypeMismatch();
    error LegacyPosition();
    error PoolMismatch();
}
