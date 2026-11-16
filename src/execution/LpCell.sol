// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISendraAddressProvider} from "../interfaces/iSendraCore/ISendraAddressProvider.sol";
import {UniswapLib} from "../lib/uniswap/Uniswap.lib.sol";

interface ILiquidityOrchestrator {
    function provideLiquidity(UniswapLib.ExecuteProvideLiquidityInput calldata input)
        external
        returns (uint256 positionId, uint256 tokenId);

    function partialClose(UniswapLib.PartialCloseInput calldata input) external;

    function sellHeld(UniswapLib.SellHeldInput calldata input) external returns (uint256 baseOut);

    function withdrawLiquidityAndCollectFees(UniswapLib.ExecuteWithdrawLiquidityAndCollectFees calldata input)
        external
        returns (uint256 baseOut);

    function collectFeesOnly(UniswapLib.ExecuteCollectFeesOnly calldata input) external returns (uint256 baseOut);
}

/// @title LpCell
/// @notice Holds every Uniswap v3 and v4 position for one owner.
/// @dev A Sendra account that already implements `lpEnabled` is used instead of this cell.
contract LpCell {
    using SafeERC20 for IERC20;

    ISendraAddressProvider public immutable addressProvider;
    address public owner;
    uint256 private locked = 1;

    constructor(address _addressProvider, address _owner) {
        if (_owner == address(0)) revert ZeroOwner();
        addressProvider = ISendraAddressProvider(_addressProvider);
        owner = _owner;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier nonReentrant() {
        if (locked != 1) revert Reentrancy();
        locked = 2;
        _;
        locked = 1;
    }

    function lpEnabled() external pure returns (bool) {
        return true;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function push(address token, address to, uint256 amount) external {
        if (msg.sender != addressProvider.getAddress("LiquidityOrchestrator")) revert NotOrchestrator();
        IERC20(token).safeTransfer(to, amount);
    }

    function provide(UniswapLib.ExecuteProvideLiquidityInput calldata input)
        external
        onlyOwner
        nonReentrant
        returns (uint256 positionId)
    {
        if (input.provideLiquidityInput.user != owner) revert NotOwner();
        address base = input.swapInput0.tokenIn;
        if (input.swapInput1.tokenIn != base) revert BaseMismatch();
        uint256 total = input.swapInput0.amountIn0 + input.swapInput1.amountIn0;
        address orch = addressProvider.getAddress("LiquidityOrchestrator");
        if (total > 0) {
            IERC20(base).safeTransferFrom(owner, address(this), total);
            IERC20(base).forceApprove(orch, total);
        }
        _approvePositions();
        (positionId,) = ILiquidityOrchestrator(orch).provideLiquidity(input);
    }

    function partialClose(UniswapLib.PartialCloseInput calldata input) external onlyOwner nonReentrant {
        if (input.user != owner) revert NotOwner();
        _approvePositions();
        ILiquidityOrchestrator(addressProvider.getAddress("LiquidityOrchestrator")).partialClose(input);
    }

    function sellHeld(UniswapLib.SellHeldInput calldata input) external onlyOwner nonReentrant returns (uint256 baseOut) {
        if (input.user != owner) revert NotOwner();
        baseOut = ILiquidityOrchestrator(addressProvider.getAddress("LiquidityOrchestrator")).sellHeld(input);
    }

    function withdraw(UniswapLib.ExecuteWithdrawLiquidityAndCollectFees calldata input)
        external
        onlyOwner
        nonReentrant
        returns (uint256 baseOut)
    {
        if (input.withdrawInput.user != owner) revert NotOwner();
        _approvePositions();
        baseOut = ILiquidityOrchestrator(addressProvider.getAddress("LiquidityOrchestrator")).withdrawLiquidityAndCollectFees(input);
    }

    function collectFees(UniswapLib.ExecuteCollectFeesOnly calldata input)
        external
        onlyOwner
        nonReentrant
        returns (uint256 baseOut)
    {
        if (input.collectInput.user != owner) revert NotOwner();
        _approvePositions();
        baseOut = ILiquidityOrchestrator(addressProvider.getAddress("LiquidityOrchestrator")).collectFeesOnly(input);
    }

    function _approvePositions() internal {
        IERC721(addressProvider.getAddress("UniswapNFTPositionManager")).setApprovalForAll(
            addressProvider.getAddress("LiquidityManager"), true
        );
        IERC721(addressProvider.getAddress("UniswapV4PositionManager")).setApprovalForAll(
            addressProvider.getAddress("LiquidityManagerV4"), true
        );
    }

    error NotOwner();
    error NotOrchestrator();
    error ZeroOwner();
    error Reentrancy();
    error BaseMismatch();
}
