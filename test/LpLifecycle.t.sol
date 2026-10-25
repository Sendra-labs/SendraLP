// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IHooks} from "@uniswap/v4-core/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/types/Currency.sol";
import {LiquidityOrchestrator} from "../src/core/uniswap/executors/LiquidityOrchestrator.sol";
import {LiquidityManagerV3} from "../src/core/uniswap/executors/LiquidityManagerV3.sol";
import {LiquidityManagerV4} from "../src/core/uniswap/executors/LiquidityManagerV4.sol";
import {LpAccounts} from "../src/storage/LpAccounts.sol";
import {LpCell} from "../src/execution/LpCell.sol";
import {LpData} from "../src/lib/uniswap/LpData.sol";
import {SendraLib} from "../src/lib/Sendra.lib.sol";
import {UniswapLib} from "../src/lib/uniswap/Uniswap.lib.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockNpm, MockV3Pool} from "./mocks/MockNpm.sol";
import {MockPermit2, MockPoolManager, MockV4PositionManager} from "./mocks/MockV4.sol";
import {MockProvider, MockRoles, MockAccountsManager, MockAccountAccess, MockStorage, MockInitializer, MockSwapRouter} from "./mocks/MockCore.sol";

contract LpLifecycleTest is Test {
    uint256 internal constant A = 1 ether;
    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    MockERC20 internal usdc;
    MockERC20 internal weth;
    address internal token0;
    address internal token1;

    MockProvider internal provider;
    MockStorage internal store;
    MockNpm internal npm;
    MockV4PositionManager internal v4;
    LpAccounts internal accounts;
    LiquidityOrchestrator internal orch;

    address internal user = makeAddr("user");
    address internal other = makeAddr("other");

    function setUp() public {
        usdc = new MockERC20("USDC");
        weth = new MockERC20("WETH");
        if (address(usdc) < address(weth)) {
            token0 = address(usdc);
            token1 = address(weth);
        } else {
            token0 = address(weth);
            token1 = address(usdc);
        }

        npm = new MockNpm();
        v4 = new MockV4PositionManager();
        MockV3Pool pool = new MockV3Pool();
        MockPoolManager pools = new MockPoolManager();
        vm.etch(PERMIT2, address(new MockPermit2()).code);

        provider = new MockProvider();
        store = new MockStorage();
        MockInitializer init = new MockInitializer(store);
        MockRoles roles = new MockRoles();
        MockAccountsManager accountsManager = new MockAccountsManager();
        MockAccountAccess access = new MockAccountAccess();
        MockSwapRouter router = new MockSwapRouter();

        provider.set("UniswapNFTPositionManager", address(npm));
        provider.set("UniswapV3Factory", address(pool));
        provider.set("UniswapV4PositionManager", address(v4));
        provider.set("UniswapV4PoolManager", address(pools));
        provider.set("Roles", address(roles));
        provider.set("SendraStorage", address(store));
        provider.set("PositionInitializer", address(init));
        provider.set("AccountsManager", address(accountsManager));
        provider.set("AccountAccessControl", address(access));
        provider.set("SwapRouter", address(router));

        LiquidityManagerV3 managerV3 = new LiquidityManagerV3(address(provider));
        LiquidityManagerV4 managerV4 = new LiquidityManagerV4(address(provider));
        provider.set("LiquidityManager", address(managerV3));
        provider.set("LiquidityManagerV4", address(managerV4));

        accounts = new LpAccounts(address(provider));
        provider.set("LpAccounts", address(accounts));
        orch = new LiquidityOrchestrator(address(provider));
        provider.set("LiquidityOrchestrator", address(orch));

        usdc.mint(user, 100 ether);
        usdc.mint(other, 100 ether);
        vm.prank(user);
        usdc.approve(address(1), 0);
    }

    function test_spotAccountIsTheLpAccount() public {
        address spot = address(new LpCell(address(provider), user));
        MockAccountsManager(address(provider.addr("AccountsManager"))).setAccount(user, spot);

        vm.startPrank(user);
        usdc.approve(spot, type(uint256).max);
        uint256 id = LpCell(spot).provide(_order(user, UniswapLib.Protocol.UniswapV3));
        vm.stopPrank();

        assertEq(abi.decode(store.getUserPositionById(user, id).positionData[LpData.RECIPIENT], (address)), spot);
        vm.prank(user);
        assertEq(accounts.open(), spot);
        assertEq(accounts.cellFor(other), address(0));
    }

    function test_ownerWithoutLpOnSpotGetsACell() public {
        address foreign = address(new MockERC20("NO"));
        MockAccountsManager(address(provider.addr("AccountsManager"))).setAccount(user, foreign);
        vm.prank(user);
        address cell = accounts.open();
        assertTrue(cell != foreign);
        assertEq(LpCell(cell).owner(), user);
        assertEq(accounts.cellFor(user), cell);
    }

    function test_oneCellPerUser() public {
        address first = _cell(user);
        vm.prank(user);
        assertEq(accounts.open(), first);
        address second = _cell(other);
        assertTrue(second != first);
        assertEq(LpCell(first).owner(), user);
        assertTrue(LpCell(first).lpEnabled());
    }

    function test_v3OpenPartialAndSell() public {
        address cell = _cell(user);
        uint256 id = _provide(user, cell, UniswapLib.Protocol.UniswapV3);
        SendraLib.Position memory position = store.getUserPositionById(user, id);

        assertEq(position.positionType, LpData.POSITION_TYPE);
        assertTrue(position.isActive);
        assertEq(abi.decode(position.positionData[LpData.PROTOCOL], (uint8)), uint8(UniswapLib.Protocol.UniswapV3));
        assertEq(abi.decode(position.positionData[LpData.PHASE], (uint8)), LpData.PHASE_LIVE);
        assertEq(abi.decode(position.positionData[LpData.RECIPIENT], (address)), cell);
        assertEq(abi.decode(position.positionData[LpData.BASE], (address)), address(usdc));
        assertEq(abi.decode(position.positionData[LpData.INITIAL_USD], (uint256)), 2 * A);
        assertEq(abi.decode(position.positionData[LpData.CHAIN_ID], (uint256)), block.chainid);
        assertEq(store.globalPulses(), 1);
        assertEq(store.specificPulses(), 1);
        assertEq(store.lastUser(), user);
        assertEq(store.activeOf(user), 1);

        uint256 idle = usdc.balanceOf(user);
        vm.prank(user);
        LpCell(cell).partialClose(_partial(user, position));
        position = store.getUserPositionById(user, id);
        assertTrue(position.isActive);
        assertEq(abi.decode(position.positionData[LpData.PHASE], (uint8)), LpData.PHASE_HOLDING);
        assertEq(usdc.balanceOf(user), idle);
        assertEq(store.globalPulses(), 1);
        assertEq(store.activeOf(user), 1);
        assertEq(_tokenBalance(cell, token0), A);
        assertEq(_tokenBalance(cell, token1), A);

        position = store.getUserPositionById(user, id);
        vm.expectRevert(LiquidityOrchestrator.WrongPhase.selector);
        vm.prank(user);
        LpCell(cell).partialClose(_partial(user, position));

        vm.prank(user);
        uint256 got = LpCell(cell).sellHeld(_sell(user, id));
        position = store.getUserPositionById(user, id);
        assertEq(got, 2 * A);
        assertFalse(position.isActive);
        assertEq(position.pnl, 0);
        assertEq(abi.decode(position.positionData[LpData.PHASE], (uint8)), LpData.PHASE_CLOSED);
        assertEq(usdc.balanceOf(user), idle + 2 * A);
        assertEq(store.activeOf(user), 0);
        assertEq(store.globalPulses(), 2);
        assertEq(_tokenBalance(cell, token0), 0);
        assertEq(_tokenBalance(cell, token1), 0);
    }

    function test_v3FeesStayOnThePositionUntilSold() public {
        address cell = _cell(user);
        uint256 id = _provide(user, cell, UniswapLib.Protocol.UniswapV3);
        uint256 tokenId = abi.decode(store.getUserPositionById(user, id).positionData[LpData.TOKEN_ID], (uint256));
        npm.accrue(tokenId, 0.2 ether, 0.3 ether);

        SendraLib.Position memory opened = store.getUserPositionById(user, id);
        vm.prank(user);
        LpCell(cell).partialClose(_partial(user, opened));
        uint256 before = usdc.balanceOf(user);
        vm.prank(user);
        uint256 got = LpCell(cell).sellHeld(_sell(user, id));

        SendraLib.Position memory position = store.getUserPositionById(user, id);
        assertEq(got, 2 * A + 0.5 ether);
        assertEq(position.pnl, int256(0.5 ether));
        assertEq(abi.decode(position.positionData[LpData.FEES_USD], (uint256)), 0.5 ether);
        assertEq(usdc.balanceOf(user), before + got);
    }

    function test_v3CollectFeesDoesNotClose() public {
        address cell = _cell(user);
        uint256 id = _provide(user, cell, UniswapLib.Protocol.UniswapV3);
        uint256 tokenId = abi.decode(store.getUserPositionById(user, id).positionData[LpData.TOKEN_ID], (uint256));
        npm.accrue(tokenId, 0.2 ether, 0.3 ether);
        uint256 before = usdc.balanceOf(user);

        vm.prank(user);
        uint256 got = LpCell(cell).collectFees(_collect(user, id, tokenId));
        SendraLib.Position memory position = store.getUserPositionById(user, id);

        assertEq(got, 0.5 ether);
        assertEq(usdc.balanceOf(user), before + got);
        assertTrue(position.isActive);
        assertEq(abi.decode(position.positionData[LpData.PHASE], (uint8)), LpData.PHASE_LIVE);
        assertEq(abi.decode(position.positionData[LpData.FEES_USD], (uint256)), 0.5 ether);
        assertEq(store.globalPulses(), 1);
        assertEq(store.activeOf(user), 1);
    }

    function test_v3FullCloseSwapsImmediately() public {
        address cell = _cell(user);
        uint256 id = _provide(user, cell, UniswapLib.Protocol.UniswapV3);
        uint256 spent = 100 ether - usdc.balanceOf(user);
        uint256 tokenId = abi.decode(store.getUserPositionById(user, id).positionData[LpData.TOKEN_ID], (uint256));

        vm.prank(user);
        uint256 got = LpCell(cell).withdraw(_withdraw(user, id, tokenId));
        SendraLib.Position memory position = store.getUserPositionById(user, id);

        assertEq(spent, 2 * A);
        assertEq(got, 2 * A);
        assertEq(position.pnl, 0);
        assertFalse(position.isActive);
        assertEq(usdc.balanceOf(user), 100 ether);
        assertEq(store.activeOf(user), 0);
    }

    function test_v3LeftoverIsReturnedInBase() public {
        npm.setTakeBps(5_000);
        address cell = _cell(user);
        uint256 id = _provide(user, cell, UniswapLib.Protocol.UniswapV3);
        SendraLib.Position memory position = store.getUserPositionById(user, id);

        assertEq(abi.decode(position.positionData[LpData.INITIAL_USD], (uint256)), A);
        assertEq(abi.decode(position.positionData[LpData.AMOUNT0], (uint256)), A / 2);
        assertEq(abi.decode(position.positionData[LpData.AMOUNT1], (uint256)), A / 2);
        assertEq(usdc.balanceOf(user), 100 ether - A);
    }

    function test_v4UsesSamePositionTypeAndAccount() public {
        address cell = _cell(user);
        uint256 v3Id = _provide(user, cell, UniswapLib.Protocol.UniswapV3);
        uint256 v4Id = _provide(user, cell, UniswapLib.Protocol.UniswapV4);

        SendraLib.Position memory first = store.getUserPositionById(user, v3Id);
        SendraLib.Position memory second = store.getUserPositionById(user, v4Id);
        assertEq(abi.decode(first.positionData[LpData.RECIPIENT], (address)), cell);
        assertEq(abi.decode(second.positionData[LpData.RECIPIENT], (address)), cell);
        assertEq(second.positionType, LpData.POSITION_TYPE);
        assertEq(abi.decode(second.positionData[LpData.PROTOCOL], (uint8)), uint8(UniswapLib.Protocol.UniswapV4));
        assertEq(abi.decode(second.positionData[LpData.TICK_SPACING], (int24)), int24(60));
        assertEq(abi.decode(second.positionData[LpData.HOOKS], (address)), address(0));
        assertEq(abi.decode(second.positionData[LpData.POOL_ID], (bytes32)), PoolId.unwrap(_key().toId()));
        assertEq(store.activeOf(user), 2);

        vm.prank(user);
        LpCell(cell).partialClose(_partial(user, second));
        assertEq(abi.decode(store.getUserPositionById(user, v3Id).positionData[LpData.PHASE], (uint8)), LpData.PHASE_LIVE);
        assertEq(abi.decode(store.getUserPositionById(user, v4Id).positionData[LpData.PHASE], (uint8)), LpData.PHASE_HOLDING);
        assertEq(store.activeOf(user), 2);

        vm.prank(user);
        uint256 got = LpCell(cell).sellHeld(_sell(user, v4Id));
        assertEq(got, 2 * A);
        assertTrue(store.getUserPositionById(user, v3Id).isActive);
        assertFalse(store.getUserPositionById(user, v4Id).isActive);
        assertEq(store.activeOf(user), 1);
    }

    function test_rejectsDirectCallAndEarlySell() public {
        address cell = _cell(user);
        vm.expectRevert(LiquidityOrchestrator.NotLpCell.selector);
        vm.prank(user);
        orch.provideLiquidity(_order(user, UniswapLib.Protocol.UniswapV3));

        uint256 id = _provide(user, cell, UniswapLib.Protocol.UniswapV3);
        vm.expectRevert(LiquidityOrchestrator.WrongPhase.selector);
        vm.prank(user);
        LpCell(cell).sellHeld(_sell(user, id));

        UniswapLib.ExecuteProvideLiquidityInput memory native = _order(user, UniswapLib.Protocol.UniswapV3);
        native.provideLiquidityInput.token0 = address(0);
        vm.expectRevert(LiquidityOrchestrator.NativeCurrency.selector);
        vm.prank(cell);
        orch.provideLiquidity(native);
    }

    function _cell(address owner) internal returns (address cell) {
        vm.startPrank(owner);
        cell = accounts.open();
        usdc.approve(cell, type(uint256).max);
        vm.stopPrank();
    }

    function _provide(address owner, address cell, UniswapLib.Protocol protocol) internal returns (uint256 id) {
        vm.prank(owner);
        id = LpCell(cell).provide(_order(owner, protocol));
    }

    function _order(address owner, UniswapLib.Protocol protocol)
        internal
        view
        returns (UniswapLib.ExecuteProvideLiquidityInput memory input)
    {
        input.swapInput0 = _buy(token0, A);
        input.swapInput1 = _buy(token1, A);
        input.invertedSwapInput0 = _route(token0);
        input.invertedSwapInput1 = _route(token1);
        input.provideLiquidityInput = UniswapLib.ProvideLiquidityInput({
            protocol: protocol,
            token0: token0,
            token1: token1,
            recipient: address(0),
            user: owner,
            amount0: A,
            amount1: A,
            tickLower: -600,
            tickUpper: 600,
            fee: 3000,
            tickSpacing: protocol == UniswapLib.Protocol.UniswapV4 ? int24(60) : int24(0),
            hooks: address(0)
        });
    }

    function _partial(address owner, SendraLib.Position memory position)
        internal
        pure
        returns (UniswapLib.PartialCloseInput memory input)
    {
        input.uniId = abi.decode(position.positionData[LpData.TOKEN_ID], (uint256));
        input.positionId = position.id;
        input.user = owner;
    }

    function _sell(address owner, uint256 positionId) internal view returns (UniswapLib.SellHeldInput memory input) {
        input.positionId = positionId;
        input.user = owner;
        input.swapInput0 = _route(token0);
        input.swapInput1 = _route(token1);
    }

    function _withdraw(address owner, uint256 positionId, uint256 tokenId)
        internal
        view
        returns (UniswapLib.ExecuteWithdrawLiquidityAndCollectFees memory input)
    {
        input.withdrawInput = UniswapLib.WithdrawInput({uniId: tokenId, positionId: positionId, user: owner});
        input.swapInput0 = _route(token0);
        input.swapInput1 = _route(token1);
    }

    function _collect(address owner, uint256 positionId, uint256 tokenId)
        internal
        view
        returns (UniswapLib.ExecuteCollectFeesOnly memory input)
    {
        input.collectInput = UniswapLib.CollectInput({uniId: tokenId, positionId: positionId, user: owner});
        input.swapInput0 = _route(token0);
        input.swapInput1 = _route(token1);
    }

    function _buy(address token, uint256 amount) internal view returns (UniswapLib.SwapInput memory swap) {
        swap.tokenIn = address(usdc);
        swap.tokenOut = token;
        swap.amountIn0 = amount;
        if (token == address(usdc)) return swap;
        swap.swapInstructions = new UniswapLib.SwapInstruction[](1);
        swap.swapInstructions[0] = _hop(address(usdc), token, amount);
    }

    function _route(address token) internal view returns (UniswapLib.SwapInput memory swap) {
        swap.tokenIn = token;
        swap.tokenOut = address(usdc);
        if (token == address(usdc)) return swap;
        swap.swapInstructions = new UniswapLib.SwapInstruction[](1);
        swap.swapInstructions[0] = _hop(token, address(usdc), 1);
    }

    function _hop(address tokenIn, address tokenOut, uint256 amount)
        internal
        pure
        returns (UniswapLib.SwapInstruction memory hop)
    {
        hop.protocol = UniswapLib.Protocol.UniswapV3;
        hop.tokenIn = tokenIn;
        hop.tokenOut = tokenOut;
        hop.amountIn = amount;
        hop.fee = 3000;
    }

    function _key() internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
    }

    function _tokenBalance(address holder, address token) internal view returns (uint256) {
        return MockERC20(token).balanceOf(holder);
    }
}
