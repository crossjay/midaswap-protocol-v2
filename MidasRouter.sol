// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "./MidasVault.sol";
import "./interfaces/ILBRouter.sol";
import "./libraries/TokenHelper.sol";



/// @title Midas Router
/// @author midaswap
/// @notice Midas Router provides the interfaces to trade and manage the liquidity positions.
/// Midas Router interacts with Midas NFT Vault to process the NFT assets.
/// This version is just sample of test. It only works for ERC721 assets.

contract MidasRouter {
    
    using TokenHelper for IERC20;

    IERC20[] public tokenPath;

    ILBRouter public immutable LBRouter;
    MidasVault public immutable midasVault;

    constructor(ILBRouter _LBRouter, address _midasVault) {
        LBRouter = _LBRouter;
        midasVault = MidasVault(_midasVault);
    }

    function create(
        address _nftAddress,
        address _ftAddress,
        uint24 _activeId,
        uint id
    ) external returns (ILBPair pair, address _fractionAddress) {
        _fractionAddress = midasVault.createFractionsToken(_nftAddress, id);
        pair = LBRouter.createLBPair(IERC20(_fractionAddress), IERC20(_ftAddress), _activeId);
    }

    /// @notice This function is meant to buy the specific NFTs by providing NFT ids.
    function buyNFT(
        uint256 _amountInMax,
        address _nftAddress,
        uint256[] calldata _tokenIds,
        IERC20 _ftAddress,
        address _to,
        uint256 _deadline
    ) external returns (uint256[] memory amountsIn) {
        /// Get the address of vToken
        address _fractionAddress = midasVault.getERC721FractionAddress(_nftAddress);
        /// Swap for the exact amount of vToken
        tokenPath = new IERC20[](2);
        tokenPath[0] = _ftAddress;
        tokenPath[1] = IERC20(_fractionAddress);
        tokenPath[0].approve(address(LBRouter), _amountInMax);
        amountsIn = LBRouter.swapTokensForExactTokens(_tokenIds.length*1e18, _amountInMax, tokenPath, _to, _deadline);
        /// Withdraw the NFT from the Vault
        IERC20(_fractionAddress).approve(address(LBRouter), _tokenIds.length*1e18);
        midasVault.convertFractionToNFT(_nftAddress, address(_ftAddress), _tokenIds.length*1e18, _to);
    }

    function buyNFTFromETH(
        address _nftAddress,
        uint256[] calldata _tokenIds,
        IERC20 _ftAddress,
        address _to,
        uint256 _deadline
    ) external returns (uint256[] memory amountsIn) {
        /// Get the address of vToken
        address _fractionAddress = midasVault.getERC721FractionAddress(_nftAddress);
        /// Swap for the exact amount of vToken
        tokenPath = new IERC20[](2);
        tokenPath[0] = _ftAddress;
        tokenPath[1] = IERC20(_fractionAddress);
        amountsIn = LBRouter.swapETHForExactTokens(_tokenIds.length*1e18, tokenPath, _to, _deadline);
        /// Withdraw the NFT from the Vault
        IERC20(_fractionAddress).approve(address(LBRouter), _tokenIds.length*1e18);
        midasVault.convertFractionToNFT(_nftAddress, address(_ftAddress), _tokenIds.length*1e18, _to);
    }

    function sellNFT(
        uint256 _amountOutMin,
        address _nftAddress,
        uint256[] calldata _tokenIds,
        IERC20 _ftAddress,
        address _to,
        uint256 _deadline
    ) external returns (uint256 amountOut) {
        /// Get the address of vToken
        address _fractionAddress = midasVault.getERC721FractionAddress(_nftAddress);
        /// Swap the exact amount of FT
        tokenPath = new IERC20[](2);
        tokenPath[0] = IERC20(_fractionAddress);
        tokenPath[1] = _ftAddress;
        /// Deposit the NFT into the Vault
        midasVault.sellNFTFromTrader(_to, _nftAddress, address(_ftAddress), _tokenIds);
        IERC20(_fractionAddress).approve(address(LBRouter), _tokenIds.length*1e18);
        amountOut = LBRouter.swapExactTokensForTokens(_tokenIds.length*1e18, _amountOutMin, tokenPath, _to, _deadline);
    }

    function sellNFTToETH(
        uint256 _amountIn,
        uint256 _amountOutMin,
        address _nftAddress,
        uint256[] calldata _tokenIds,
        IERC20 _ftAddress,
        address payable _to,
        uint256 _deadline
    ) external returns (uint256 amountOut) {
        /// Get the address of vToken
        address _fractionAddress = midasVault.getERC721FractionAddress(_nftAddress);
        /// Swap the exact amount of FT
        tokenPath = new IERC20[](2);
        tokenPath[0] = IERC20(_fractionAddress);
        tokenPath[1] = _ftAddress;
        amountOut = LBRouter.swapExactTokensForETH(_amountIn, _amountOutMin, tokenPath, _to, _deadline);
        /// Deposit the NFT into the Vault
        for (uint i = 0; i < _tokenIds.length; i++) {
            IERC721(_nftAddress).approve(address(midasVault), _tokenIds[i]);
        }
        midasVault.sellNFTFromTrader(_to, _nftAddress, address(_ftAddress), _tokenIds);
    }


    // function addLiquidityETH


    // function removeLiquidity


    // function removeLiquidityETH

}