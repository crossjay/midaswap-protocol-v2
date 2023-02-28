// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

interface IMidasFactory721 {

    event OwnerChanged(address indexed oldOwner, address indexed newOwner);

    event FeeRateChanged(uint128 indexed oldFee, uint128 indexed newFee);

    event PairCreated(
        address indexed tokenX,
        address indexed tokenY,
        uint128 indexed feeRate,
        address pair,
        address lpToken
    );

    function createERC721Pair(
        address _token0,
        address _token1
    ) external returns (address lpToken, address pair);

    function feeRecipient() external view returns (address _feeRecipient);

    function getPairERC721(
        address tokenA,
        address tokenB
    ) external view returns (address pair);

    function getLPTokenERC721(
        address tokenA,
        address tokenB
    ) external view returns (address lpToken);


}
