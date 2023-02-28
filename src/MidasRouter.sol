// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./libraries/TokenHelper.sol";
import "./libraries/PriceHelper.sol";
import "./interfaces/IRoyaltyEngineV1.sol";
import "./interfaces/IMidasRouter.sol";
import "./interfaces/IMidasFactory721.sol";
import "./interfaces/IMidasPair721.sol";
import "./interfaces/IWETH.sol";

/// @title Midas Router
/// @author midaswap
/// @notice Router for trades and liquidity managements against the Midaswap

contract MidasRouter is IMidasRouter {

    using TokenHelper for IERC20;
    using TokenHelper for IWETH;

    // address public immutable factory;
    // address public immutable WETH;
    IMidasFactory721 public factory;
    IWETH public weth;
    IRoyaltyEngineV1 public royaltyEngine;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'MidaswapRouter: EXPIRED');
        _;
    }

    constructor (
        IMidasFactory721 _factory,
        IWETH _weth,
        IRoyaltyEngineV1 _royaltyEngine
    ) {
        factory = _factory;
        weth = _weth;
        royaltyEngine = _royaltyEngine;
    }

    receive() external payable {
        assert(msg.sender == address(weth)); // only accept ETH via fallback from the WETH contract
    }

    // function createPair(
    //     address _tokenX,
    //     address _tokenY
    // ) external override returns (address lpToken, address pair) {
    //     (lpToken, pair) = factory.createERC721Pair(_tokenX, _tokenY);
    // }

    function addLiquidityERC721(
        address _tokenX,
        address _tokenY,
        uint24[] calldata _ids,
        uint256[] calldata _tokenIds,
        uint256 _deadline
    ) external override ensure(_deadline) returns (uint256 idAmount, uint256 lpTokenId) {
        address _pair = factory.getPairERC721(_tokenX, _tokenY);
        for (uint i = 0; i < _tokenIds.length; i++) {
            IERC721(_tokenX).approve(_pair, _tokenIds[i]);
        }
        (idAmount, lpTokenId) = IMidasPair721(_pair).mintNFT(_ids, _tokenIds, msg.sender, false);
    }

    function addLiquidityERC20(
        address _tokenX,
        address _tokenY,
        uint24[] calldata _ids,
        uint256 _deadline
    ) external override ensure(_deadline) returns (uint256 idAmount, uint256 lpTokenId) {
        require(_tokenY != address(weth), "MIDASROUTER: WRONG PAIR");
        address _pair = factory.getPairERC721(_tokenX, _tokenY);
        uint256 _amount = _getAmountsToAdd(_pair, _ids);
        IERC20(_tokenY).safeTransferFrom(msg.sender, _pair, _amount);
        (idAmount, lpTokenId) = IMidasPair721(_pair).mintFT(_ids, msg.sender);
    }

    function addLiquidityETH(
        address _tokenX,
        address _tokenY,
        uint24[] calldata _ids,
        uint256 _deadline
    ) external override payable ensure(_deadline) returns (uint256 idAmount, uint256 lpTokenId) {
        address _pair = factory.getPairERC721(_tokenX, _tokenY);
        uint256 _amount = _getAmountsToAdd(_pair, _ids);
        require(_tokenY == address(weth) && msg.value >= _amount, "MIDASROUTER: WRONG PAIR");
        _wethDepositAndTransfer(_pair, msg.value);
        (idAmount, lpTokenId) = IMidasPair721(_pair).mintFT(_ids, msg.sender);
    }

    function removeLiquidity(
        address _tokenX,
        address _tokenY,
        uint256 _lpTokenId,
        uint256 _deadline
    ) external override ensure(_deadline) returns (uint256 nftAmount, uint256 ftAmount) {
        require(_tokenY != address(weth), "MIDASROUTER: WRONG PAIR");
        address _pair = factory.getPairERC721(_tokenX, _tokenY);
        address _lpToken = factory.getLPTokenERC721(_tokenX, _tokenY);
        IERC721(_lpToken).safeTransferFrom(msg.sender, _pair, _lpTokenId);
        (nftAmount, ftAmount) = IMidasPair721(_pair).burn(_lpTokenId, msg.sender);
        IERC20(_tokenY).safeTransfer(msg.sender, ftAmount);
    }

    function removeLiquidityETH(
        address _tokenX,
        address _tokenY,
        uint256 _lpTokenId,
        uint256 _deadline
    ) external override ensure(_deadline) returns (uint256 nftAmount, uint256 ftAmount) {
        require(_tokenY == address(weth), "MIDASROUTER: WRONG PAIR");
        address _pair = factory.getPairERC721(_tokenX, _tokenY);
        address _lpToken = factory.getLPTokenERC721(_tokenX, _tokenY);
        IERC721(_lpToken).safeTransferFrom(msg.sender, _pair, _lpTokenId);
        (nftAmount, ftAmount) = IMidasPair721(_pair).burn(_lpTokenId, msg.sender);
        weth.withdraw(ftAmount);
        _safeTransferETH(msg.sender, ftAmount);
    }

    function sellItems(
        address _tokenX,
        address _tokenY,
        uint256[] calldata _tokenIds,
        uint256 _deadline
    ) external override ensure(_deadline) returns (uint256 _ftAmount) {
        require(_tokenY != address(weth), "MIDASROUTER: WRONG PAIR");
        address _pair = factory.getPairERC721(_tokenX, _tokenY);
        for (uint i = 0; i < _tokenIds.length; i++) {
            IERC721(_tokenX).approve(_pair, _tokenIds[i]);
            _ftAmount = IMidasPair721(_pair).sellNFT(_tokenIds[i], msg.sender);
            IERC20(_tokenY).safeTransfer(msg.sender, _ftAmount);
        }
    }

    function sellItemsToETH(
        address _tokenX,
        address _tokenY,
        uint256[] calldata _tokenIds,
        uint256 _deadline
    ) external override payable ensure(_deadline) returns (uint256 _ftAmount) {
        require(_tokenY == address(weth), "MIDASROUTER: WRONG PAIR");
        address _pair = factory.getPairERC721(_tokenX, _tokenY);
        for (uint i = 0; i < _tokenIds.length; i++) {
            IERC721(_tokenX).approve(_pair, _tokenIds[i]);
            _ftAmount = IMidasPair721(_pair).sellNFT(_tokenIds[i], msg.sender);
            weth.withdraw(_ftAmount);
            _safeTransferETH(msg.sender, _ftAmount);
        }
    }

    function buyItems(
        address _tokenX,
        address _tokenY,
        uint256[] calldata _tokenIds,
        uint256 _deadline
    ) external override ensure(_deadline) returns (uint256 _ftAmount) {
        require(_tokenY != address(weth), "MIDASROUTER: WRONG PAIR");
        address _pair = factory.getPairERC721(_tokenX, _tokenY);
        _ftAmount = getMinAmountIn(_pair, _tokenIds);
        IERC20(_tokenY).safeTransferFrom(msg.sender, _pair, _ftAmount);
        for (uint i = 0; i < _tokenIds.length; i++) {
            IMidasPair721(_pair).buyNFT(_tokenIds[i], msg.sender);
        }
    }

    function buyItemsWithETH(
        address _tokenX,
        address _tokenY,
        uint256[] calldata _tokenIds,
        uint256 _deadline
    ) external override payable ensure(_deadline) returns (uint256 _ftAmount) {
        address _pair = factory.getPairERC721(_tokenX, _tokenY);
        _ftAmount = getMinAmountIn(_pair, _tokenIds);
        require(_tokenY == address(weth) && msg.value >= _ftAmount, "MIDASROUTER: WRONG PAIR"); 
        _wethDepositAndTransfer(_pair, msg.value);
        IERC20(_tokenY).safeTransferFrom(msg.sender, _pair, _ftAmount);
        for (uint i = 0; i < _tokenIds.length; i++) {
            IMidasPair721(_pair).buyNFT(_tokenIds[i], msg.sender);
        }
    }

    function openLimitOrder(
        address _tokenX,
        address _tokenY,
        uint24[] calldata _ids,
        uint256[] calldata _tokenIds,
        uint256 _deadline
    ) external override ensure(_deadline) returns (uint256 idAmount, uint256 lpTokenId) {
        address _pair = factory.getPairERC721(_tokenX, _tokenY);
        for (uint i = 0; i < _tokenIds.length; i++) {
            IERC721(_tokenX).approve(_pair, _tokenIds[i]);
        }
        (idAmount, lpTokenId) = IMidasPair721(_pair).mintNFT(_ids, _tokenIds, msg.sender, true);
    }

    function _getAmountsToAdd(
        address _pair,
        uint24[] calldata _ids
    ) public pure returns(uint256 ftAmount) {
        for (uint i = 0; i < _ids.length; i++) {
            ftAmount += IMidasPair721(_pair).getPriceFromBin(_ids[i]);
        }
    }

    function getMinAmountIn(
        address _pair,
        uint256[] calldata _tokenIds
    ) public view returns (uint256 totalAmount) {
        uint256[] memory lpList = new uint256[](_tokenIds.length);
        for (uint i = 0; i < _tokenIds.length; ++i) {
            lpList[i] = IMidasPair721(_pair).getLPFromNFT(_tokenIds[i]);
        }
        lpList = PriceHelper.sortDesc(lpList);
        
        uint24 _activeBin;
        uint24 _binStep;
        for(uint i = 0; i < lpList.length; ++i){
            if (i > 0 && lpList[i] == lpList[i - 1]){
                _activeBin += _binStep;
            }else{
                (_activeBin , _binStep) = IMidasPair721(_pair).getBinParamFromLP(lpList[i]);
            }
            totalAmount += IMidasPair721(_pair).getPriceFromBin(_activeBin);
        }
        (uint256 _rate1 , , uint256 _rate2) = IMidasPair721(_pair).feeParameters();
        totalAmount =  totalAmount * ( 1e18 + _rate1 + _rate2 ) / 1e18 + 1;
    } 


    function _safeTransferETH(address _to, uint256 _amount) private {
        (bool success, ) = _to.call{value: _amount}("");
        require(success == true);
    }

    function _wethDepositAndTransfer(address _to, uint256 _amount) private {
        weth.deposit{value: _amount}();
        weth.transfer(_to, _amount);
    }

}