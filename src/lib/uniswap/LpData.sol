// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Layout of a Sendra LP position. Type id stays 2 for v3 and v4.
/// Indices 0-17 match the positions already opened by LiquidityOrchestrator.
/// 18+ is the protocol tag, the partial-close book, and the v4 pool key.
library LpData {
    uint256 internal constant TOKEN0 = 0;
    uint256 internal constant TOKEN1 = 1;
    uint256 internal constant OPENED = 2;
    uint256 internal constant FEE = 3;
    uint256 internal constant TICK_LOWER = 4;
    uint256 internal constant TICK_UPPER = 5;
    uint256 internal constant AMOUNT0 = 6;
    uint256 internal constant AMOUNT1 = 7;
    uint256 internal constant RECIPIENT = 8;
    uint256 internal constant TOKEN_ID = 9;
    uint256 internal constant SQRT_OPEN = 10;
    uint256 internal constant POOL = 11;
    uint256 internal constant FINAL_USD = 12;
    uint256 internal constant SQRT_FINAL = 13;
    uint256 internal constant FEES_USD = 14;
    uint256 internal constant INITIAL_USD = 15;
    uint256 internal constant CLOSED = 16;
    uint256 internal constant CHAIN_ID = 17;
    uint256 internal constant PROTOCOL = 18;
    uint256 internal constant TICK_SPACING = 19;
    uint256 internal constant HOOKS = 20;
    uint256 internal constant PHASE = 21;
    uint256 internal constant HELD0 = 22;
    uint256 internal constant HELD1 = 23;
    uint256 internal constant FEE0 = 24;
    uint256 internal constant FEE1 = 25;
    uint256 internal constant POOL_ID = 26;
    uint256 internal constant BASE = 27;
    uint256 internal constant LEN = 28;

    /// @notice Liquidity is still in the pool.
    uint8 internal constant PHASE_LIVE = 0;
    /// @notice Pool position is gone. token0 and token1 are held until they are sold.
    uint8 internal constant PHASE_HOLDING = 1;
    /// @notice Held tokens were sold and the Sendra position is closed.
    uint8 internal constant PHASE_CLOSED = 2;

    uint128 internal constant POSITION_TYPE = 2;
}
