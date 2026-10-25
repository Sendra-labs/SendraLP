// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {INonfungiblePositionManager} from "../../../interfaces/uniswap/INonfungiblePositionManager.sol";
import {IUniswapV3Factory} from "../../../interfaces/uniswap/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "../../../interfaces/uniswap/IUniswapV3Pool.sol";
import {ISendraAddressProvider} from "../../../interfaces/iSendraCore/ISendraAddressProvider.sol";
import {ISendraRoles} from "../../../interfaces/iSendraCore/ISendraRoles.sol";
import {UniswapLib} from "../../../lib/uniswap/Uniswap.lib.sol";
import {LiquidityAmounts} from "../../../lib/uniswap/LiquidityAmounts.sol";
import {TickMath} from "@uniswap/v4-core/libraries/TickMath.sol";

/// @title LiquidityManagerV3
/// @notice Mints, collects and fully exits Uniswap v3 NFT positions. Accounting stays in the orchestrator.
contract LiquidityManagerV3 {
    using SafeERC20 for IERC20;

    ISendraAddressProvider public immutable addressProvider;
    INonfungiblePositionManager public immutable positionManager;
    IUniswapV3Factory public immutable factory;
    ISendraRoles public immutable roles;

    /// @notice Minimum share of the desired mint amount. 85 means 15% of room.
    uint256 public slippageBps = 85;

    constructor(address _addressProvider) {
        addressProvider = ISendraAddressProvider(_addressProvider);
        positionManager = INonfungiblePositionManager(addressProvider.getAddress("UniswapNFTPositionManager"));
        factory = IUniswapV3Factory(addressProvider.getAddress("UniswapV3Factory"));
        roles = ISendraRoles(addressProvider.getAddress("Roles"));
    }

    modifier onlyOrchestrator() {
        if (msg.sender != addressProvider.getAddress("LiquidityOrchestrator")) revert SenderNotAllowed();
        _;
    }

    modifier onlyAdmin() {
        if (!roles.checkAdmin(msg.sender)) revert SenderNotAllowed();
        _;
    }

    function setSlippageBps(uint256 next) external onlyAdmin {
        if (next > 100) revert SlippageTooHigh();
        slippageBps = next;
    }

    function mint(UniswapLib.ProvideLiquidityInput calldata input, address recipient)
        external
        onlyOrchestrator
        returns (UniswapLib.MintOut memory result)
    {
        if (recipient == address(0)) revert ZeroAddress();
        uint256 use0 = _usable(input.token0, input.amount0);
        uint256 use1 = _usable(input.token1, input.amount1);
        if (use0 == 0 && use1 == 0) revert ZeroLiquidity();

        if (use0 > 0) IERC20(input.token0).forceApprove(address(positionManager), use0);
        if (use1 > 0) IERC20(input.token1).forceApprove(address(positionManager), use1);

        (result.tokenId,, result.deposited0, result.deposited1) = positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: input.token0,
                token1: input.token1,
                fee: input.fee,
                tickLower: input.tickLower,
                tickUpper: input.tickUpper,
                amount0Desired: use0,
                amount1Desired: use1,
                amount0Min: (use0 * slippageBps) / 100,
                amount1Min: (use1 * slippageBps) / 100,
                recipient: recipient,
                deadline: block.timestamp + 60
            })
        );

        result.pool = factory.getPool(input.token0, input.token1, input.fee);
        if (result.pool == address(0)) revert PoolMissing();
        (result.sqrtPrice,,,,,,) = IUniswapV3Pool(result.pool).slot0();
        result.left0 = _sweep(input.token0);
        result.left1 = _sweep(input.token1);
    }

    function collect(uint256 tokenId, address recipient)
        external
        onlyOrchestrator
        returns (uint256 amount0, uint256 amount1)
    {
        return _collect(tokenId, recipient);
    }

    function exit(uint256 tokenId, int24 tickLower, int24 tickUpper, address pool, address recipient)
        external
        onlyOrchestrator
        returns (UniswapLib.ExitOut memory result)
    {
        (result.fee0, result.fee1) = _collect(tokenId, recipient);
        (,,,,,,, uint128 liquidity,,,,) = positionManager.positions(tokenId);
        (result.sqrtPrice,,,,,,) = IUniswapV3Pool(pool).slot0();

        if (liquidity > 0) {
            (uint256 expect0, uint256 expect1) = LiquidityAmounts.getAmountsForLiquidity(
                result.sqrtPrice,
                TickMath.getSqrtPriceAtTick(tickLower),
                TickMath.getSqrtPriceAtTick(tickUpper),
                liquidity
            );
            positionManager.decreaseLiquidity(
                INonfungiblePositionManager.DecreaseLiquidityParams({
                    tokenId: tokenId,
                    liquidity: liquidity,
                    amount0Min: (expect0 * 99) / 100,
                    amount1Min: (expect1 * 99) / 100,
                    deadline: block.timestamp + 60
                })
            );
        }

        (result.principal0, result.principal1) = _collect(tokenId, recipient);
        if (liquidity == 0 && result.fee0 == 0 && result.fee1 == 0 && result.principal0 == 0 && result.principal1 == 0) {
            revert NothingToExit();
        }
        positionManager.burn(tokenId);
    }

    function _collect(uint256 tokenId, address recipient) internal returns (uint256 amount0, uint256 amount1) {
        return positionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: recipient,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
    }

    function _usable(address token, uint256 wanted) internal view returns (uint256) {
        uint256 balance = IERC20(token).balanceOf(address(this));
        return balance < wanted ? balance : wanted;
    }

    function _sweep(address token) internal returns (uint256 amount) {
        amount = IERC20(token).balanceOf(address(this));
        if (amount > 0) IERC20(token).safeTransfer(msg.sender, amount);
    }

    error SenderNotAllowed();
    error SlippageTooHigh();
    error ZeroAddress();
    error ZeroLiquidity();
    error PoolMissing();
    error NothingToExit();
}
