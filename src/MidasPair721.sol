// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

/** Imports **/

import "./MidasErrors.sol";
import "./libraries/BinHelper.sol";
import "./libraries/Constants.sol";
import "./libraries/Math512Bits.sol";
import "./libraries/ReentrancyGuardUpgradeable.sol";
import "./libraries/SafeCast.sol";

import "./libraries/SwapHelper.sol";
import "./libraries/TokenHelper.sol";
import "./libraries/TreeMath.sol";
import "./interfaces/IMidasPair721.sol";

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./libraries/FeeHelper.sol";
import "./interfaces/IMidasFactory721.sol";


import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "./libraries/Math128x128.sol";
import "./libraries/BitMath.sol";


import "./libraries/PositionHelper.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "./LPToken.sol";

/// @title Midas Pair
/// @author midaswap
/// @notice This contract is the implementation of Liquidity Book Pair that also acts as the receipt token for liquidity positions
contract MidasPair721 is  ERC721Holder ,ReentrancyGuardUpgradeable, IMidasPair721 {
    /** Libraries **/

    using Math512Bits for uint256;
    using TreeMath for mapping(uint256 => uint256)[3];
    using SafeCast for uint256;

    using TokenHelper for IERC20;
    using BinHelper for uint24;
    using SwapHelper for IMidasPair721.PairInformation;
    /** Modifiers **/

    /// @notice Checks if the caller is the factory
    // modifier onlyFactory() {
    //     if (msg.sender != address(factory)) revert LBPair__OnlyFactory();
    //     _;
    // }


    /** Public immutable variables **/

    /// @notice The factory contract that created this pair
    IMidasFactory721 public immutable override factory;

    /** Public variables **/

    /// @notice The token that is used as the base currency for the pair
    IERC721 public override tokenX;

    /// @notice The token that is used as the quote currency for the pair
    IERC20 public override tokenY;

    // IRoyaltyEngineV1 public royaltyEngine;

    /** Private variables **/

    /// @dev The pair information that is used to track reserves, active ids,
    /// fees and oracle parameters
    PairInformation private _pairInformation;

    /// @dev The fee parameters that are used to calculate fees
    // FeeHelper.FeeParameters private _feeParameters;

    

    /// @dev The reserves of tokens for every bin. This is the amount
    /// of tokenY if `id < _pairInformation.activeId`; of tokenX if `id > _pairInformation.activeId`
    /// and a mix of both if `id == _pairInformation.activeId`
    mapping(uint256  => uint256[2]) private _bins;

    /// @dev The tree that is used to find the first bin with non zero liquidity
    mapping(uint256 => uint256)[3] private _tree;

    mapping(uint256 => uint256)[3] private _tree2;

    /// @dev The mapping from account to user's unclaimed fees. 
    mapping(uint256 => uint256) private _unclaimedFees;
    


    /// lpTokenId -> NFT tokenIds
    mapping (uint256 => uint256[]) private lpTokenAssetsMap;
    /// lpTokenId -> BinParams
    mapping (uint256 => BinParams) private lpBinParamsMap;
    /// NFT tokenIds -> lpTokenId
    mapping (uint256 => uint256) private assetLPMap;
    /// binIds -> lpTokenIds
    mapping (uint24 => uint256[]) private binLPMap;
    /// binIds -> ftAmounts
    mapping (uint24 => uint256[]) private ftAmountMap;


    /** constants */
    uint256 private _rate;
    uint256 private _protocolShare;
    uint256 private constant _ONE = 1e18;
    LPToken public lpToken;
    address private nftAddress;


    address payable[] private creators;
    uint256[] private creatorShares;
    uint256 private _royaltyRate; 

    /** Constructor **/

    constructor(address _factory,
                address _nftAddress,
                address _ftAddress,
                address _lpToken,
                uint128 _feeRate
                ) {
        require(address(_factory) != address(0));
        // if (address(_factory) == address(0)) revert LBPair__AddressZero();
        factory = IMidasFactory721(_factory);
        tokenX = IERC721(_nftAddress);
        tokenY = IERC20(_ftAddress);
        lpToken = LPToken(_lpToken);
        nftAddress = _nftAddress;

        __ReentrancyGuard_init();

        // royaltyEngine = IRoyaltyEngineV1(_royaltyEngine);
        _rate = _feeRate;
        unchecked{
            _protocolShare = _ONE / 10;
        }

        _tree.addToTree(0);

        // _royaltyRate = _royalRate;
        // (creators, creatorShares) = royaltyEngine.getRoyaltyView(_nftAddress, _testTokenId, _ONE);
        
        // unchecked{
        //     uint256 royalSum;
        //     for (uint i = 0; i < creators.length ; ++i){
        //         royalSum += creatorShares[i] ;
        //     }
        //     for (uint i = 0; i < creators.length ; ++i){
        //         creatorShares[i] = creatorShares[i] * _ONE / royalSum - 1;
        //     }
        // }
    }

    /** External View Functions **/

    function getReservesAndId()
        external
        view
        override
        returns (
            uint256 reserveX,
            uint256 reserveY,
            uint256 floorPriceID,
            uint256 bestOfferID
        )
    {   
        
        reserveX = _pairInformation.reserveX;
        reserveY = _pairInformation.reserveY;
        floorPriceID = _pairInformation.floorPriceID;
        bestOfferID = _pairInformation.bestOfferID;
    }



    function getGlobalFees()
        external
        view
        override
        returns (
            uint256 feesYTotal,
            uint256 feesYProtocol
        )
    {
        feesYTotal = _pairInformation.feesTotal;
        feesYProtocol = _pairInformation.feesProtocol;
    }


    /// @notice View function to get the fee parameters
    /// @return The fee parameters
    function feeParameters() external view override returns (uint256 , uint256 ,uint256) {
        return (_rate , _protocolShare , _royaltyRate );
    }


    /// @notice View function to get the bin at `id`
    /// @param _id The bin id
    /// @return reserveX The reserve of tokenX of the bin
    /// @return reserveY The reserve of tokenY of the bin
    function getBin(uint24 _id) external view override returns (uint256, uint256) {
        
        return (_bins[_id][0], _bins[_id][1]);
    }

    function getFee(uint256 _LPtokenID)  
        external 
        view 
        override
        returns(uint256 _fee)
    {
        _fee = _unclaimedFees[_LPtokenID];
    }

    function getPriceFromBin(uint24 _id)
        external 
        pure 
        override
        returns(uint256)
    {
        return _getPriceFromBin( _id);
    }


    function getLPFromNFT(uint256 _NFTID)
        external 
        view 
        override
        returns(uint256 _LPtoken)
    { 
        _LPtoken = assetLPMap[_NFTID];
        // _activeBin = lpBinParamsMap[_LPtoken].activeBin;
        // _binStep = lpBinParamsMap[_LPtoken].binStep;
    }


    function getBinParamFromLP(uint256 _LPtoken)
        external 
        view
        override
        returns(uint24 _activeBin , uint24 _binStep)
    {
        _activeBin = lpBinParamsMap[_LPtoken].activeBin;
        _binStep = lpBinParamsMap[_LPtoken].binStep;
    }

    


    // function getBalance()
    //     external
    //     view
    //     returns(uint256)
    // {   
        
    //     return _pairInformation.feesRoyalty;
    // }
    

    

    
    /** External Functions **/

    
    function sellNFT(uint256 NFTID, address _to)
        external
        override
        nonReentrant
        returns (uint256 _amountOut)
    {
        PairInformation memory _pair = _pairInformation;

    

        uint24 _tradeID = _pair.floorPriceID;
        uint256[2] memory _bin = _bins[_tradeID];

        // if (_bin[1] == 0) revert LBPair__InsufficientLiquidityMinted(_tradeID);
        require(_bin[1] > 0);

        uint256 _amountOutOfBin = _getPriceFromBin(_tradeID);
        unchecked{
        _amountOut = _amountOutOfBin - FeeHelper.getFeeAmount( (_rate + _royaltyRate) , _amountOutOfBin) ;
        }
        (uint256 _feesTotal , uint256 _feesProtocol , uint256 _feesRoyalty) = FeeHelper.getFeeAmountDistributionWithRoyalty(_amountOut , _rate , _protocolShare , _royaltyRate);
        
        uint256 lpIndex = PositionHelper._findNonZeroIndex(ftAmountMap[_tradeID]);
        uint256 _LPtokenID = binLPMap[_tradeID][lpIndex];
        tokenX.safeTransferFrom(_to, address(this), NFTID);
        _updateFTAmount(_LPtokenID, _tradeID, _ONE, true);
        lpTokenAssetsMap[_LPtokenID].push(NFTID);
        unchecked{
        lpBinParamsMap[_LPtokenID].activeBin -= lpBinParamsMap[_LPtokenID].binStep;
        
        _unclaimedFees[_LPtokenID] += _feesTotal - _feesProtocol;
        }
        

        _pair.updateFees( _feesTotal , _feesProtocol);
        _pair.updateRoyaltyFees(_feesRoyalty);
        _pair.updateReserves(_bin, true, _ONE, _amountOutOfBin);

        if (_bin[0] == _ONE) _tree2.addToTree(_tradeID);
        if (_bin[1] == 0) _tree.removeFromTree(_tradeID);

        (_pair.floorPriceID , _pair.bestOfferID) = TreeMath.updateActiveBin(_tree , _tree2 , _pair);
            
        _bins[_tradeID] = _bin;
        _pairInformation = _pair;

        tokenY.safeTransfer(_to, _amountOut);

    }



    function buyNFT(uint256 NFTID , address _to)
        external
        override
        nonReentrant
    {   
        PairInformation memory _pair = _pairInformation;

        

        
        uint256 _LPtokenID = assetLPMap[NFTID];
        uint256[] memory tokenArr = lpTokenAssetsMap[_LPtokenID];
        uint24 _tradeId = lpBinParamsMap[_LPtokenID].activeBin;
        tokenX.safeTransferFrom(address(this), _to, NFTID);
        unchecked{
            lpBinParamsMap[_LPtokenID].activeBin += lpBinParamsMap[_LPtokenID].binStep;
        }
        
        bool _isLimited = _LPtokenID % 2 == 1;
        uint256 tokenIndex = PositionHelper._findIndex(tokenArr, NFTID);
        lpTokenAssetsMap[_LPtokenID] = PositionHelper._removeItem(tokenArr, tokenIndex);
        delete assetLPMap[NFTID];


        

        uint256[2] memory _bin = _bins[_tradeId];
        
        if(_bin[0] == _ONE) _tree2.removeFromTree(_tradeId);
        if(_bin[1] == 0) _tree.addToTree(_tradeId);
        


        uint256 _amountInToBin = _getPriceFromBin(_tradeId);
    
        (uint256 _feesTotal , uint256 _feesProtocol , uint256 _feesRoyalty) = FeeHelper.getFeeAmountDistributionWithRoyalty(_amountInToBin , _rate , _protocolShare , _royaltyRate);
        
        
        unchecked{
            // if(_amountInToBin + _feesTotal + _feesRoyalty > tokenY.received(_pair.reserveY , _pair.feesTotal + _pair.feesRoyalty)) revert LBPair__InsufficientLiquidityMinted(_tradeId);
            require(_amountInToBin + _feesTotal + _feesRoyalty <= tokenY.received(_pair.reserveY , _pair.feesTotal + _pair.feesRoyalty));

            _pair.updateRoyaltyFees(_feesRoyalty);

            if(_isLimited){
                _unclaimedFees[_LPtokenID] += _amountInToBin + _feesTotal - _feesProtocol;
                _pair.updateFees(_amountInToBin + _feesTotal , _feesProtocol);
                _pair.updateReserves(_bin, false, uint256(0), _ONE);
            }else{
                _unclaimedFees[_LPtokenID] += _feesTotal - _feesProtocol;
                _pair.updateFees( _feesTotal , _feesProtocol);
                _pair.updateReserves(_bin, false, _amountInToBin, _ONE);

                _updateFTAmount(_LPtokenID, _tradeId, _ONE, false);

            }
        }
        

        (_pair.floorPriceID , _pair.bestOfferID) = TreeMath.updateActiveBin(_tree , _tree2 , _pair);


        

        _bins[_tradeId] = _bin;
        _pairInformation = _pair;

    }



   
    function mintNFT(
        uint24[] calldata _ids,
        uint256[] calldata _NFTIDs,
        address _to,
        bool isLimited
    )
        external
        override
        nonReentrant
        returns (
            uint256,
            uint256
        )
    {
        // if (_ids.length == 0 || _ids.length != _NFTIDs.length)
        //     revert LBPair__WrongLengths();
        require(_ids.length > 0 && _ids.length == _NFTIDs.length);
        PairInformation memory _pair = _pairInformation;

        (_pair.currentPositionID % 2 == 0) == (isLimited) ? _pair.currentPositionID +=1 : _pair.currentPositionID +=2 ;
        uint256 _LPtokenID = _pair.currentPositionID;
        
        lpToken.mint(_to , _LPtokenID);


        require(PositionHelper._checkBinSequence(_ids));
        /// Initiate the active bin of this part of liquidity
        lpBinParamsMap[_LPtokenID].originBin = _ids[0];
        lpBinParamsMap[_LPtokenID].activeBin =  _ids[0];
        lpBinParamsMap[_LPtokenID].binStep = PositionHelper._getBinStep(_ids);
        lpBinParamsMap[_LPtokenID].binAmount = _ids.length;

        for (uint i = 0; i < _NFTIDs.length; i++) {
            tokenX.safeTransferFrom(_to, address(this), _NFTIDs[i]);
            assetLPMap[_NFTIDs[i]] = _LPtokenID;
            binLPMap[_ids[i]].push(_LPtokenID);
            ftAmountMap[_ids[i]].push(0);
        }

        lpTokenAssetsMap[_LPtokenID] = _NFTIDs;

        
        //Error还没写
        // if (_ids[0] < _pair.floorPriceID) revert LBPair__InsufficientLiquidityMinted(_ids[0]);
        require(_ids[0] >= _pair.floorPriceID);

        uint24 _id;
        for (uint256 i; i < _ids.length; ) {
            _id = _ids[i];
            uint256[2] memory _bin = _bins[_id];

            if (_bin[0] == 0) _tree2.addToTree(_id);

            unchecked {
                _bin[0] += _ONE;
                _pair.reserveX += _ONE.safe136();
                _bins[_id] = _bin;
                ++i;
            }

        }

        (_pair.floorPriceID , _pair.bestOfferID) = TreeMath.updateActiveBin(_tree , _tree2 , _pair);


        _pairInformation = _pair;

        return (_ids.length , _LPtokenID);
    }


    function mintFT(
        uint24[] calldata _ids,
        address _to
    )
        external
        override
        nonReentrant
        returns (
            uint256,
            uint256
        )
    {
        PairInformation memory _pair = _pairInformation;

        uint256 _amountYIn;
        uint24 _mintId;
        uint256 _amountYAddedToPair;
        
        unchecked{
            _pair.currentPositionID % 2 == 0 ? _pair.currentPositionID +=2 : _pair.currentPositionID +=1 ;
        }

        uint256 _LPtokenID = _pair.currentPositionID;
        lpToken.mint(_to , _LPtokenID);

        require(PositionHelper._checkBinSequence(_ids));
        for (uint i = 0; i < _ids.length; ) {
            binLPMap[_ids[i]].push(_LPtokenID);
            ftAmountMap[_ids[i]].push(_ONE);
            unchecked{
                ++i;
            }
        }

        /// Initiate the active bin of this part of liquidity
        unchecked{
        lpBinParamsMap[_LPtokenID].originBin = _ids[0];
        lpBinParamsMap[_LPtokenID].binStep = PositionHelper._getBinStep(_ids);
        lpBinParamsMap[_LPtokenID].activeBin = _ids[_ids.length - 1] + lpBinParamsMap[_LPtokenID].binStep;
        lpBinParamsMap[_LPtokenID].binAmount = _ids.length;
        }
        _amountYIn = tokenY.received(_pair.reserveY, _pair.feesTotal + _pair.feesRoyalty);

        //Error还没写
        // if (_ids[_ids.length-1] > _pair.bestOfferID && _pair.bestOfferID != 0) revert LBPair__InsufficientLiquidityMinted(_ids[_ids.length-1]);
        require(_ids[_ids.length-1] <= _pair.bestOfferID || _pair.bestOfferID == 0);

        unchecked{
            for (uint256 i; i < _ids.length; ++i) {
                _mintId = _ids[i];
                uint256[2] memory _bin = _bins[_mintId];

                if (_bin[1] == 0) _tree.addToTree(_mintId);

                uint256 _price = _getPriceFromBin(_mintId);
                _bin[1] += _price;
                _pair.reserveY += _price.safe136();
                _amountYAddedToPair += _price;

                _bins[_mintId] = _bin;
            }
        }
        //error还没写
        // if(_amountYAddedToPair > _amountYIn) revert LBPair__DistributionsOverflow();
        require(_amountYAddedToPair <= _amountYIn);

        (_pair.floorPriceID , _pair.bestOfferID) = TreeMath.updateActiveBin(_tree , _tree2 , _pair);
        _pairInformation = _pair;

        return (_amountYAddedToPair, _LPtokenID);
    }


    function burn(
        uint256 _LPtokenID,
        address _to
    ) external override nonReentrant returns (uint256 amountX, uint256 amountY) {
        


        PairInformation memory _pair = _pairInformation;

        
        uint256[] memory _tokenIds = lpTokenAssetsMap[_LPtokenID];
        for (uint i = 0; i < _tokenIds.length; ) {
            tokenX.safeTransferFrom(address(this), _to, _tokenIds[i]);
            delete assetLPMap[_tokenIds[i]];
            unchecked {
                ++i;
            }
        }

        uint256 _binIdLength = lpBinParamsMap[_LPtokenID].binAmount;
        uint24 originBin = lpBinParamsMap[_LPtokenID].originBin;
        uint24 binStep = lpBinParamsMap[_LPtokenID].binStep;

        uint24[] memory _ids;
        bool[] memory _isNFTs;

        _ids = new uint24[](_binIdLength);
        _isNFTs = new bool[](_binIdLength);

        unchecked{
            for (uint i = 0; i < _binIdLength; ++i ) {
            
                uint24 newBin = originBin + uint24(i) * binStep;
            
                _ids[i] = newBin;
                _removeLP(_LPtokenID, newBin);
                if (i < _binIdLength - _tokenIds.length) {
                    _isNFTs[i] = false;
                } else {
                    _isNFTs[i] = true;
                }
            }
        }
        delete lpTokenAssetsMap[_LPtokenID];
        delete lpBinParamsMap[_LPtokenID];


        unchecked {
            for (uint256 i; i < _ids.length; ++i) {
                uint24 _id = _ids[i];
                uint256[2] memory _bin = _bins[_id];
                if (_isNFTs[i]) {
                    amountX += _ONE;
                    _bin[0] -= _ONE;
                    _pair.reserveX -= _ONE.safe136();
                    if (_bin[0] == 0) _tree2.removeFromTree(_id);
                }else if( _LPtokenID % 2 == 0){
                    uint256 _price = _getPriceFromBin(_id);
                    amountY += _price;
                    _bin[1] -= _price;
                    _pair.reserveY -= _price.safe136();
                    if (_bin[1] == 0) _tree.removeFromTree(_id);
                }


                _bins[_id] = _bin;
            }
        }

        (_pair.floorPriceID , _pair.bestOfferID) = TreeMath.updateActiveBin(_tree , _tree2 , _pair);
        _pairInformation = _pair;

        uint256 amountFee = _unclaimedFees[_LPtokenID];
        unchecked{
            if (amountFee != 0) {
            delete _unclaimedFees[_LPtokenID];
            _pairInformation.feesTotal -= amountFee;

            tokenY.safeTransfer(_to, amountFee);
            }
        }

        tokenY.safeTransfer(_to, amountY);

        lpToken.burn(_LPtokenID);
    }


    /// @notice Collect the protocol fees and send them to the fee recipient.
    /// @dev The protocol fees are not set to zero to save gas by not resetting the storage slot.
    /// @return amountY The amount of token Y collected and sent to the fee recipient
    function collectProtocolFees() external override nonReentrant returns (uint256 amountY) {
        address _feeRecipient = factory.feeRecipient();

        // if (msg.sender != _feeRecipient) revert LBPair__OnlyFeeRecipient(_feeRecipient, msg.sender);
        require(msg.sender == _feeRecipient);

        amountY = _pairInformation.feesProtocol;
        // unchecked{
        //     if (amountY  > 1) {
        //     amountY -=  1;
        //     _pairInformation.feesTotal -= amountY;
        //     _pairInformation.feesProtocol = 1;

        //     tokenY.safeTransfer(_feeRecipient, amountY);
        //     }
        // }
        

        unchecked{
            
            _pairInformation.feesTotal -= amountY;
            delete _pairInformation.feesProtocol ;

            tokenY.safeTransfer(_feeRecipient, amountY);
            
        }


        
    }

    function collectRoyaltyFees() external override nonReentrant returns (uint256 _royaltyFees) {

        _royaltyFees = _pairInformation.feesRoyalty;
        delete _pairInformation.feesRoyalty;
        
        unchecked{
            
            for (uint i = 0; i < creators.length ; ++i){
                tokenY.safeTransfer(creators[i], creatorShares[i] * _royaltyFees / _ONE - 1);
            }
        }
    }

    function updateRoyalty(uint256 _newRate , address payable[] calldata newrecipients, uint256[] calldata newshares) external {
        // if (msg.sender != address(factory)) revert LBPair__OnlyFactory();
        require(msg.sender == address(factory));
        creators = newrecipients;
        creatorShares = newshares;
        _royaltyRate = _newRate;
    }




    // function flashLoan(
    //     ILBFlashLoanCallback _receiver,
    //     IERC721 _token,
    //     uint256 _NFTID,
    //     bytes calldata _data
    // ) external override nonReentrant {
    //     // 检测机制需要更新
    //     if (_token != tokenX) revert LBPair__FlashLoanInvalidToken();

    //     // ERC721.safeTransferFrom(address(this) , address(_receiver), _NFTID);

    //     // if (
    //     //     _receiver.LBFlashLoanCallback(msg.sender, _token, _amount, _data) != Constants.CALLBACK_SUCCESS
    //     // ) revert LBPair__FlashLoanCallbackFailed();


    //     // if (_balanceAfter != _balanceBefore) revert LBPair__FlashLoanInvalidBalance();

    //     // emit FlashLoan(msg.sender, _receiver, _token, _amount);
    // }



    /** Internal Functions **/

    function _getPriceFromBin(uint24 _id)
        private 
        pure 
        returns(uint256 _price)
    {
        _price = _id.getPriceFromId();
        _price = _price.mulShiftRoundDown(_ONE, Constants.SCALE_OFFSET);
    }

    // function _emitSwap(
    //     address _to,
    //     uint256 _NFTID,
    //     uint24 _Id,
    //     bool _swapForY,
    //     uint256 _amountInToBin,
    //     uint256 _amountOutOfBin,
    //     uint256 _fees
    // ) private {
    //     emit Swap(
    //         msg.sender,
    //         _to,
    //         _NFTID,
    //         _Id,
    //         _swapForY,
    //         _amountInToBin,
    //         _amountOutOfBin,
    //         _fees
    //     );
    // }

    function _removeLP(
        uint256 _lpTokenId,
        uint24 _binId   
    ) internal returns (bool) {
        uint256 lpIndex = PositionHelper._findIndex(binLPMap[_binId], _lpTokenId);
        binLPMap[_binId] = PositionHelper._removeItem(binLPMap[_binId], lpIndex);
        ftAmountMap[_binId] = PositionHelper._removeItem(ftAmountMap[_binId], lpIndex);
        return true;
    }

    function _updateFTAmount(
        uint256 _lpTokenId,
        uint24 _binId,
        uint256 _amount,
        bool direction
    ) internal returns (uint256 newAmount) {
        unchecked{
            uint256 lpIndex = PositionHelper._findIndex(binLPMap[_binId], _lpTokenId);
            uint256 lastAmount = ftAmountMap[_binId][lpIndex];
            if (direction == true) {
                require(lastAmount >= _amount);
                newAmount = lastAmount - _amount;
                
            } else {
                newAmount = lastAmount + _amount;
            }
            ftAmountMap[_binId][lpIndex] = newAmount;
        }
        
    }


    // function _sendRoyaltyFee(
    //     uint256 tokenId,
    //     uint256 salesPrice,
    //     bool swapForY
    // ) internal returns (
    //     uint256 feesTotal,
    //     uint256 feesProtocol,
    //     uint256 feesRoyalty
    // ){  
    //     unchecked{
            
    //         (address payable[] memory recipients, uint256[] memory amounts) = royaltyEngine.getRoyaltyView(nftAddress, tokenId, _ONE);
    //         uint256 royalRate;
    //         uint256 sumFee;
    //         for (uint i = 0; i < amounts.length ; i++){
    //             royalRate += amounts[i] ;
    //         }
    //         uint256 sumRate = royalRate + _rate ;
    //         uint256 feeBase;
    //         if(swapForY){
    //             sumFee = sumRate.getFeeAmount(salesPrice);
    //             feeBase = salesPrice - sumFee ;
    //         }else{
    //             sumFee = sumRate.getFeeAmountFrom(salesPrice);
    //             feeBase = salesPrice;
    //         }
    //         for (uint i = 0; i < amounts.length ; i++){
    //             tokenY.safeTransfer(recipients[i], amounts[i] * feeBase);
    //         }
    //         feesTotal = feeBase * _rate;
    //         feesProtocol = feesTotal * _protocolShare;
    //         feesRoyalty = feeBase * royalRate;
    //     }
    // }



    // function _sendRoyaltyFeeBuy(
    //     uint256 tokenId,
    //     uint256 salesPrice
    // ) internal returns (
    //     uint256 feesTotal,
    //     uint256 feesProtocol
    // ){
    //     (address payable[] memory recipients, uint256[] memory amounts) = royaltyEngine.getRoyaltyView(nftAddress, tokenId, salesPrice);
    //     for (uint i = 0; i < amounts.length ; i++){
    //         tokenY.safeTransfer(recipients[i], amounts[i]);
    //     }
    //     feesTotal = _rate.getFeeAmountFrom(salesPrice);
    //     feesProtocol = _protocolShare * feesTotal;
    // }


    // function _sendRoyaltyFeeSell(
    //     uint256 tokenId,
    //     uint256 salesPrice
    // ) internal returns (
    //     uint256 feesTotal,
    //     uint256 feesProtocol,
    //     uint256 feesRoyalty
    // ){
    //     (address payable[] memory recipients, uint256[] memory amounts) = royaltyEngine.getRoyaltyView(nftAddress, tokenId, _ONE);
    //     uint256 royalRate;
    //     for (uint i = 0; i < amounts.length ; i++){
    //         royalRate += amounts[i] ;
    //     }

    //     uint256 feeBase = salesPrice - (royalRate + _rate).getFeeAmount(salesPrice); 
        
    //     for (uint i = 0; i < amounts.length ; i++){
    //         tokenY.safeTransfer(recipients[i], amounts[i] * feeBase);
    //     }
    //     feesTotal = feeBase * _rate;
    //     feesProtocol = feesTotal * _protocolShare;
    //     feesRoyalty = feeBase * royalRate;

    // }



    // function _depositNFT(
    //     uint256 _lpTokenId,
    //     uint256[] calldata _tokenIds,
    //     uint24[] calldata _binIds,
    //     address lp
    // ) internal returns (bool) {
    //     require(PositionHelper._checkBinSequence(_binIds));
    //     /// Initiate the active bin of this part of liquidity
    //     lpBinParamsMap[_lpTokenId].originBin = _binIds[0];
    //     lpBinParamsMap[_lpTokenId].activeBin =  _binIds[0];
    //     lpBinParamsMap[_lpTokenId].binStep = PositionHelper._getBinStep(_binIds);
    //     lpBinParamsMap[_lpTokenId].binAmount = _binIds.length;

    //     for (uint i = 0; i < _tokenIds.length; i++) {
    //         tokenX.safeTransferFrom(lp, address(this), _tokenIds[i]);
    //         assetLPMap[_tokenIds[i]] = _lpTokenId;
    //         binLPMap[_binIds[i]].push(_lpTokenId);
    //         ftAmountMap[_binIds[i]].push(0);
    //     }

    //     lpTokenAssetsMap[_lpTokenId] = _tokenIds;
    //     return true;
    // }


    // function _withdraw(
    //     uint256 _lpTokenId,
    //     address lp
    // ) internal returns (uint24[] memory _binIds, bool[] memory _assetsList) {
    //     uint256[] memory _tokenIds = lpTokenAssetsMap[_lpTokenId];
    //     for (uint i = 0; i < _tokenIds.length; i++) {
    //         tokenX.safeTransferFrom(address(this), lp, _tokenIds[i]);
    //         delete assetLPMap[_tokenIds[i]];
    //     }

    //     uint256 _binIdLength = lpBinParamsMap[_lpTokenId].binAmount;
    //     uint24 originBin = lpBinParamsMap[_lpTokenId].originBin;
    //     uint24 binStep = lpBinParamsMap[_lpTokenId].binStep;
    //     uint256 nftSold = _binIdLength - _tokenIds.length;

    //     for (uint24 i = 0; i < _binIdLength; i++) {
    //         uint24 newBin = originBin + i*binStep;
    //         _binIds[_binIds.length] = newBin;
    //         _removeLP(_lpTokenId, newBin);
    //         if (i < nftSold) {
    //             _assetsList[_assetsList.length] = false;
    //         } else {
    //             _assetsList[_assetsList.length] = true;
    //         }
    //     }

    //     delete lpTokenAssetsMap[_lpTokenId];
    //     delete lpBinParamsMap[_lpTokenId];
    // }

    /* ========== TRADER'S OPERATIONS ========== */

    // function _sellNFT(
    //     uint256 _tokenId,
    //     uint24 _floorPriceBin,
    //     address seller
    // ) internal returns (uint256 lpTokenId) {
    //     uint256 lpIndex = PositionHelper._findNonZeroIndex(ftAmountMap[_floorPriceBin]);
    //     lpTokenId = binLPMap[_floorPriceBin][lpIndex];
    //     tokenX.safeTransferFrom(seller, address(this), _tokenId);
    //     _updateFTAmount(lpTokenId, _floorPriceBin, _ONE, true);
    //     lpTokenAssetsMap[lpTokenId].push(_tokenId);
    //     lpBinParamsMap[lpTokenId].activeBin -= lpBinParamsMap[lpTokenId].binStep;
    // }

    // function _buyNFT(
    //     uint256 _tokenId,
    //     address buyer
    // ) internal returns (uint24 binId, uint256 lpTokenId) {
    //     lpTokenId = assetLPMap[_tokenId];
    //     uint256[] memory tokenArr = lpTokenAssetsMap[lpTokenId];
    //     binId = lpBinParamsMap[lpTokenId].activeBin;
    //     tokenX.safeTransferFrom(address(this), buyer, _tokenId);
    //     lpBinParamsMap[lpTokenId].activeBin += lpBinParamsMap[lpTokenId].binStep;
    //     _updateFTAmount(lpTokenId, binId, _ONE, false);
    //     uint256 tokenIndex = PositionHelper._findIndex(tokenArr, _tokenId);
    //     lpTokenAssetsMap[lpTokenId] = PositionHelper._removeItem(tokenArr, tokenIndex);
    //     delete assetLPMap[_tokenId];
    // }
}