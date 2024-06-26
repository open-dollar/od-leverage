// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.7.6;
pragma abicoder v2;

import "@algebra-core/interfaces/callback/IAlgebraFlashCallback.sol";
import "@algebra-core/interfaces/IAlgebraFactory.sol";
import "@algebra-core/libraries/LowGasSafeMath.sol";

import "@algebra-periphery/base/PeripheryPayments.sol";
import "@algebra-periphery/base/PeripheryImmutableState.sol";
import "@algebra-periphery/libraries/PoolAddress.sol";
import "@algebra-periphery/libraries/CallbackValidation.sol";
import "@algebra-periphery/libraries/TransferHelper.sol";
import "@algebra-periphery/interfaces/ISwapRouter.sol";

contract AlgebraFlash is IAlgebraFlashCallback, PeripheryImmutableState, PeripheryPayments {
    using LowGasSafeMath for uint256;
    using LowGasSafeMath for int256;

    address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    ISwapRouter public immutable swapRouter;

    struct FlashParams {
        address token0;
        address token1;
        uint256 amount0;
        uint256 amount1;
    }

    struct FlashCallbackData {
        uint256 amount0;
        uint256 amount1;
        address payer;
        PoolAddress.PoolKey poolKey;
    }

    constructor(ISwapRouter _swapRouter, address _factory)
        PeripheryImmutableState(_factory, WETH, IAlgebraFactory(_factory).poolDeployer())
    {
        swapRouter = _swapRouter;
    }

    function algebraFlashCallback(uint256 fee0, uint256 fee1, bytes calldata data) external override {
        FlashCallbackData memory decoded = abi.decode(data, (FlashCallbackData));
        CallbackValidation.verifyCallback(factory, decoded.poolKey);

        address token0 = decoded.poolKey.token0;
        address token1 = decoded.poolKey.token1;

        TransferHelper.safeApprove(token0, address(swapRouter), decoded.amount0);
        TransferHelper.safeApprove(token1, address(swapRouter), decoded.amount1);

        uint256 amount1Min = LowGasSafeMath.add(decoded.amount1, fee1);
        uint256 amount0Min = LowGasSafeMath.add(decoded.amount0, fee0);

        // call exactInputSingle for swapping token1 for token0 in pool
        uint256 amountOut0 = swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: token1,
                tokenOut: token0,
                recipient: address(this),
                deadline: block.timestamp + 60,
                amountIn: decoded.amount1,
                amountOutMinimum: amount0Min,
                limitSqrtPrice: 0
            })
        );

        // call exactInputSingle for swapping token0 for token 1 in pool
        uint256 amountOut1 = swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: token0,
                tokenOut: token1,
                recipient: address(this),
                deadline: block.timestamp + 60,
                amountIn: decoded.amount0,
                amountOutMinimum: amount1Min,
                limitSqrtPrice: 0
            })
        );

        uint256 amount0Owed = LowGasSafeMath.add(decoded.amount0, fee0);
        uint256 amount1Owed = LowGasSafeMath.add(decoded.amount1, fee1);

        TransferHelper.safeApprove(token0, address(this), amount0Owed);
        TransferHelper.safeApprove(token1, address(this), amount1Owed);

        if (amount0Owed > 0) pay(token0, address(this), msg.sender, amount0Owed);
        if (amount1Owed > 0) pay(token1, address(this), msg.sender, amount1Owed);

        // if profitable pay profits to payer
        if (amountOut0 > amount0Owed) {
            uint256 profit0 = LowGasSafeMath.sub(amountOut0, amount0Owed);

            TransferHelper.safeApprove(token0, address(this), profit0);
            pay(token0, address(this), decoded.payer, profit0);
        }
        if (amountOut1 > amount1Owed) {
            uint256 profit1 = LowGasSafeMath.sub(amountOut1, amount1Owed);
            TransferHelper.safeApprove(token0, address(this), profit1);
            pay(token1, address(this), decoded.payer, profit1);
        }
    }

    function initFlash(FlashParams memory params) external {
        PoolAddress.PoolKey memory poolKey = PoolAddress.PoolKey({token0: params.token0, token1: params.token1});
        IAlgebraPool pool = IAlgebraPool(PoolAddress.computeAddress(factory, poolKey));
        pool.flash(
            address(this),
            params.amount0,
            params.amount1,
            abi.encode(
                FlashCallbackData({
                    amount0: params.amount0,
                    amount1: params.amount1,
                    payer: msg.sender,
                    poolKey: poolKey
                })
            )
        );
    }
}
