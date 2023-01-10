// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./libraries/TokenHelper.sol";
import "./interfaces/ILBRouter.sol";

abstract contract LBRouterLiquidityMidas is ILBRouter {

    using TokenHelper for IERC20;

    ILBRouter public router = ILBRouter(0x3a50e976Fb91B2E13bD1391936f958fcE1e11c96); 

    function mintNewPosition () external returns (uint256[] memory depositIds, uint256[] memory liquidityMinted) {
        uint256 PRECISION = 1e18;
        uint256 binStep = 25;
        uint256 amountX = 100 * 10e6;
        uint256 amountY = 100 * 10e6;
        uint256 amountXmin = 99 * 10e6; // We allow 1% amount slippage
        uint256 amountYmin = 99 * 10e6; // We allow 1% amount slippage

        uint256 activeIdDesired = 2**23; // We get the ID from price using getIdFromPrice()
        uint256 idSlippage = 5;

        uint256 binsAmount = 3;
        int256[] memory deltaIds = new int256[](binsAmount);
        deltaIds[0] = -1;
        deltaIds[1] = 0;
        deltaIds[2] = 1;
        uint256[] memory distributionX = new uint256[](binsAmount);
        distributionX[0] = 0;
        distributionX[1] = PRECISION / 2;
        distributionX[2] = PRECISION / 2;

        uint256[] memory distributionY = new uint256[](binsAmount);
        distributionY[0] = (2 * PRECISION) / 3;
        distributionY[1] = PRECISION / 3;
        distributionY[2] = 0;
        
        IERC20 tokenX = 0x1a6Ce7ABA7bFc23a823526Ecea850b9Fb25CFd37;
        IERC20 tokenY = 0x077de8Ef4882a3537c100007fd0d18d8a902C4e3;
        address receiver = 0x4AF34038ae489E60D8e8cF1CF76b8AF63daE1A97;

        ILBRouter.LiquidityParameters memory liquidityParameters = ILBRouter.LiquidityParameters(
            tokenX,
            tokenY,
            binStep,
            amountX,
            amountY,
            amountXmin,
            amountYmin,
            activeIdDesired,
            idSlippage,
            deltaIds,
            distributionX,
            distributionY,
            0x4AF34038ae489E60D8e8cF1CF76b8AF63daE1A97,
            block.timestamp
        );

        tokenX.approve(address(ILBRouter), amountX);
        tokenY.approve(address(ILBRouter), amountY);

        (uint256[] memory depositIds, uint256[] memory liquidityMinted) = ILBRouter.addLiquidity(liquidityParameters);
    }
    
}
