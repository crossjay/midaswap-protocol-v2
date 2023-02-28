// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

/// @title Midas Router Interfaces
/// @author midaswap
/// @notice Providing the interfaces for trading and managing liquidity position

interface IMidasRouter {
    
    // function createPair(
    //     address _tokenX,
    //     address _tokenY
    // ) external returns (address lpToken, address pair);

    function addLiquidityERC721(
        address _tokenX,
        address _tokenY,
        uint24[] calldata _ids,
        uint256[] calldata _tokenIds,
        uint256 _deadline
    ) external returns (uint256 idAmount, uint256 lpTokenId);

    function addLiquidityERC20(
        address _tokenX,
        address _tokenY,
        uint24[] calldata _ids,
        uint256 _deadline
    ) external returns (uint256 idAmount, uint256 lpTokenId);

    function addLiquidityETH(
        address _tokenX,
        address _tokenY,
        uint24[] calldata _ids,
        uint256 _deadline
    ) external payable returns (uint256 idAmount, uint256 lpTokenId);

    function removeLiquidity(
        address _tokenX,
        address _tokenY,
        uint256 _lpTokenId,
        uint256 _deadline
    ) external returns (uint256 nftAmount, uint256 ftAmount);

    function removeLiquidityETH(
        address _tokenX,
        address _tokenY,
        uint256 _lpTokenId,
        uint256 _deadline
    ) external returns (uint256 nftAmount, uint256 ftAmount);

    function sellItems(
        address _tokenX,
        address _tokenY,
        uint256[] calldata _tokenIds,
        uint256 _deadline
    ) external returns (uint256 _ftAmount);

    function sellItemsToETH(
        address _tokenX,
        address _tokenY,
        uint256[] calldata _tokenIds,
        uint256 _deadline
    ) external payable returns (uint256 _ftAmount);

    function buyItems(
        address _tokenX,
        address _tokenY,
        uint256[] calldata _tokenIds,
        uint256 _deadline
    ) external returns (uint256 _ftAmount);

    function buyItemsWithETH(
        address _tokenX,
        address _tokenY,
        uint256[] calldata _tokenIds,
        uint256 _deadline
    ) external payable returns (uint256 _ftAmount);

    function openLimitOrder(
        address _tokenX,
        address _tokenY,
        uint24[] calldata _ids,
        uint256[] calldata _tokenIds,
        uint256 _deadline
    ) external returns (uint256 idAmount, uint256 lpTokenId);
    
}