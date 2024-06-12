// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.7.6;
pragma abicoder v2;

import "@algebra-periphery/interfaces/ISwapRouter.sol";
import "@algebra-periphery/libraries/TransferHelper.sol";

/**
 * @notice msg.sender must approve this contract
 */
contract AlgebraSwap {
    address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public constant WSTETH = 0x5979D7b546E38E414F7E9822514be443A4800529;
    address public constant OD = 0x221A0f68770658C15B525d0F89F5da2baAB5f321;

    ISwapRouter public immutable swapRouter;

    constructor(ISwapRouter _swapRouter) {
        swapRouter = _swapRouter;
    }

    function swapExactInputSingle(uint256 amountIn) external returns (uint256 amountOut) {
        // transfer `amountIn` of OD to this contract
        TransferHelper.safeTransferFrom(OD, msg.sender, address(this), amountIn);

        // approve router to spend OD
        TransferHelper.safeApprove(OD, address(swapRouter), amountIn);

        // swap OD => WETH
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: OD,
            tokenOut: WETH,
            recipient: msg.sender,
            deadline: block.timestamp + 60,
            amountIn: amountIn,
            amountOutMinimum: 0,
            limitSqrtPrice: 0
        });

        // execute swap
        amountOut = swapRouter.exactInputSingle(params);
    }

    function swapExactInputMultihop(uint256 amountIn) external returns (uint256 amountOut) {
        // transfer `amountIn` of OD to this contract
        TransferHelper.safeTransferFrom(OD, msg.sender, address(this), amountIn);

        // approve router to spend OD
        TransferHelper.safeApprove(OD, address(swapRouter), amountIn);

        /**
         * swap1: OD => WETH
         * swap2: WETH => WSTETH
         */
        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: abi.encodePacked(OD, WETH, WSTETH),
            recipient: msg.sender,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0
        });

        // execute swap
        amountOut = swapRouter.exactInput(params);
    }
}
