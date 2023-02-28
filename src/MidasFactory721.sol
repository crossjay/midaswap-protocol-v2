// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "./NoDelegateCall.sol";
import "./MidasPair721.sol";
import "./LPToken.sol";
import "./interfaces/IMidasFactory721.sol";
import "./interfaces/IMidasPair721.sol"; 
import "./interfaces/IRoyaltyEngineV1.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @title Midas Pair Factory
/// @author midaswap
/// @notice Deploys Midaswap pairs and manages ownership

contract MidasFactory721 is IMidasFactory721, NoDelegateCall {
    
    address private owner;
    
    uint128 private feeEnabled;

    uint256 private royaltyRate;

    IRoyaltyEngineV1 private royaltyEngine;

    mapping(address => mapping (address => address)) public override getPairERC721;

    mapping(address => mapping (address => address)) public override getLPTokenERC721;

    constructor(uint128 _feeRate, uint256 _royaltyRate, address _royaltyEngine) {
        owner = msg.sender;
        emit OwnerChanged(address(0), msg.sender);

        feeEnabled = _feeRate;
        emit FeeRateChanged(uint128(0), feeEnabled);

        royaltyRate = _royaltyRate;

        royaltyEngine = IRoyaltyEngineV1(_royaltyEngine);
    }

    function _tokenDetector(
        address _token0,
        address _token1
    ) internal view returns (address tokenX, address tokenY) {
        bytes4 erc721Bytes = bytes4(0x80ac58cd);
        if (IERC721(_token0).supportsInterface(erc721Bytes)) {
            tokenX = _token0;
            tokenY = _token1;
        }
    }

    function feeRecipient() external view returns (address _feeRecipient) {
        _feeRecipient = owner;
    }

    function createERC721Pair(
        address _token0,
        address _token1
    ) external override noDelegateCall returns (address lpToken, address pair) {
        require(_token0 != _token1);
        (address _tokenX, address _tokenY) = _tokenDetector(_token0, _token1);
        require(_tokenY != address(0));
        require(getPairERC721[_tokenX][_tokenY] == address(0));
        (lpToken, pair) = deployERC721(address(this), _tokenX, _tokenY, feeEnabled);
        setRoyaltyInfo(_tokenX, pair, royaltyRate);
        // (address payable[] memory _recipients, uint256[] memory _shares) = royaltyEngine.getRoyaltyView(_tokenX, 1, 1e18);
        // IMidasPair721(pair).updateRoyalty(uint256(0), _recipients, _shares);
        
        LPToken(lpToken).initialize(pair);
        getPairERC721[_tokenX][_tokenY] = pair;
        getLPTokenERC721[_tokenX][_tokenY] = lpToken;
        emit PairCreated(_tokenX, _tokenY, feeEnabled, pair, lpToken);
    }

    function setOwner(address _owner) external {
        require(msg.sender == owner);
        emit OwnerChanged(owner, _owner);
        owner = _owner;
    }

    function setRoyaltyInfo(
        address _nftAddress,
        address _pair,
        uint256 _newRate
    ) public  {
        require(msg.sender == owner);
        royaltyRate = _newRate;
        (address payable[] memory _recipients, uint256[] memory _shares) = royaltyEngine.getRoyaltyView(_nftAddress, 1, 1e18);
        if (_shares.length > 0) {
            uint256 _shareSum;
            for (uint i = 0; i < _shares.length; ++i) {
                _shareSum += _shares[i] ;
            }
            for (uint i = 0; i < _shares.length; ++i) {
                _shares[i] = _shares[i] * 1e18 / _shareSum - 1;
            }
            IMidasPair721(_pair).updateRoyalty(royaltyRate, _recipients, _shares);
        } else {
            
            IMidasPair721(_pair).updateRoyalty(uint256(0), _recipients, _shares);
        }
    }

    function deployERC721(
        address _factory,
        address _tokenX,
        address _tokenY,
        uint128 _feeRate
    ) internal returns (address _lpToken, address pair) {
        _lpToken = address(new LPToken{salt: keccak256(abi.encode(_tokenX, _tokenY))}("MidasLPToken", "MLPT", _factory));
        pair = address(new MidasPair721{salt: keccak256(abi.encode(_tokenX, _tokenY))}(_factory, _tokenX, _tokenY, _lpToken, _feeRate));
        // parameters1 = ERC721Parameters({factory: _factory, tokenX: _tokenX, tokenY: _tokenY, lpToken: _lpToken, feeRate: _feeRate});
        // delete parameters1;
    }
}