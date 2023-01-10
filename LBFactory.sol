// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./LBErrors.sol";
import "./libraries/BinHelper.sol";
import "./libraries/Constants.sol";
import "./libraries/Decoder.sol";
import "./libraries/PendingOwnable.sol";
import "./libraries/SafeCast.sol";
import "./interfaces/ILBFactory.sol";

/// @title Liquidity Book Factory
/// @author Trader Joe
/// @notice Contract used to deploy and register new LBPairs.
/// Enables setting fee parameters, flashloan fees and LBPair implementation.
/// Unless the `creationUnlocked` is `true`, only the owner of the factory can create pairs.
contract LBFactory is PendingOwnable, ILBFactory {
    using SafeCast for uint256;
    using Decoder for bytes32;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public constant override MAX_FEE = 0.1e18; // 10%

    address public override LBPairImplementation;

    address public override feeRecipient;

    /// @notice Whether the createLBPair function is unlocked and can be called by anyone (true) or only by owner (false)
    bool public override creationUnlocked;

    uint256 public override flashLoanFee;

    ILBPair[] public override allLBPairs;

    /// @dev Mapping from a (tokenA, tokenB, binStep) to a LBPair. The tokens are ordered to save gas, but they can be
    /// in the reverse order in the actual pair. Always query one of the 2 tokens of the pair to assert the order of the 2 tokens
    mapping(IERC20 => mapping(IERC20 => LBPairInformation)) private _LBPairsInfo;

    /// @dev Whether a preset was set or not, if the bit at `index` is 1, it means that the binStep `index` was set
    /// The max binStep set is 247. We use this method instead of an array to keep it ordered and to reduce gas
    bytes32 private _availablePresets;

    // The parameters presets
    mapping(uint256 => bytes32) private _presets;

    EnumerableSet.AddressSet private _quoteAssetWhitelist;


    /// @notice Constructor
    /// @param _feeRecipient The address of the fee recipient
    constructor(address _feeRecipient) {
        _setFeeRecipient(_feeRecipient);
    }

    /// @notice View function to return the number of LBPairs created
    /// @return The number of LBPair
    function getNumberOfLBPairs() external view override returns (uint256) {
        return allLBPairs.length;
    }

    /// @notice View function to return the number of quote assets whitelisted
    /// @return The number of quote assets
    function getNumberOfQuoteAssets() external view override returns (uint256) {
        return _quoteAssetWhitelist.length();
    }

    /// @notice View function to return the quote asset whitelisted at index `index`
    /// @param _index The index
    /// @return The address of the _quoteAsset at index `index`
    function getQuoteAsset(uint256 _index) external view override returns (IERC20) {
        return IERC20(_quoteAssetWhitelist.at(_index));
    }

    /// @notice View function to return whether a token is a quotedAsset (true) or not (false)
    /// @param _token The address of the asset
    /// @return Whether the token is a quote asset or not
    function isQuoteAsset(IERC20 _token) external view override returns (bool) {
        return _quoteAssetWhitelist.contains(address(_token));
    }

    /// @notice Returns the LBPairInformation if it exists,
    /// if not, then the address 0 is returned. The order doesn't matter
    /// @param _tokenA The address of the first token of the pair
    /// @param _tokenB The address of the second token of the pair
    /// @return The LBPairInformation
    function getLBPairInformation(
        IERC20 _tokenA,
        IERC20 _tokenB
    ) external view override returns (LBPairInformation memory) {
        return _getLBPairInformation(_tokenA, _tokenB);
    }

    /// @notice Set the LBPair implementation address
    /// @dev Needs to be called by the owner
    /// @param _LBPairImplementation The address of the implementation
    function setLBPairImplementation(address _LBPairImplementation) external override onlyOwner {
        if (ILBPair(_LBPairImplementation).factory() != this)
            revert LBFactory__LBPairSafetyCheckFailed(_LBPairImplementation);

        address _oldLBPairImplementation = LBPairImplementation;
        if (_oldLBPairImplementation == _LBPairImplementation)
            revert LBFactory__SameImplementation(_LBPairImplementation);

        LBPairImplementation = _LBPairImplementation;

        emit LBPairImplementationSet(_oldLBPairImplementation, _LBPairImplementation);
    }

    /// @notice Create a liquidity bin LBPair for _tokenX and _tokenY
    /// @param _tokenX The address of the first token
    /// @param _tokenY The address of the second token
    /// @param _activeId The active id of the pair
    /// @return _LBPair The address of the newly created LBPair
    function createLBPair(
        IERC20 _tokenX,
        IERC20 _tokenY,
        uint24 _activeId
    ) external override returns (ILBPair _LBPair) {
        address _owner = owner();
        if (!creationUnlocked && msg.sender != _owner) revert LBFactory__FunctionIsLockedForUsers(msg.sender);

        address _LBPairImplementation = LBPairImplementation;

        if (_LBPairImplementation == address(0)) revert LBFactory__ImplementationNotSet();

        if (!_quoteAssetWhitelist.contains(address(_tokenY))) revert LBFactory__QuoteAssetNotWhitelisted(_tokenY);

        if (_tokenX == _tokenY) revert LBFactory__IdenticalAddresses(_tokenX);

        // safety check, making sure that the price can be calculated
        BinHelper.getPriceFromId(_activeId);

        // We sort token for storage efficiency, only one input needs to be stored because they are sorted
        (IERC20 _tokenA, IERC20 _tokenB) = _sortTokens(_tokenX, _tokenY);
        // single check is sufficient
        if (address(_tokenA) == address(0)) revert LBFactory__AddressZero();
        if (address(_LBPairsInfo[_tokenA][_tokenB].LBPair) != address(0))
            revert LBFactory__LBPairAlreadyExists(_tokenX, _tokenY, 1);

        bytes32 _salt = keccak256(abi.encode(_tokenA, _tokenB));
        _LBPair = ILBPair(Clones.cloneDeterministic(_LBPairImplementation, _salt));

        _LBPair.initialize(_tokenX, _tokenY, _activeId);

        _LBPairsInfo[_tokenA][_tokenB] = LBPairInformation({
            LBPair: _LBPair,
            createdByOwner: msg.sender == _owner
        });

        allLBPairs.push(_LBPair);

        emit LBPairCreated(_tokenX, _tokenY, _LBPair, allLBPairs.length - 1);

        // emit FeeParametersSet(
        //     msg.sender,
        //     _LBPair,
        //     _binStep,
        //     _preset.decode(type(uint16).max, 16),
        //     _preset.decode(type(uint16).max, 32),
        //     _preset.decode(type(uint16).max, 48),
        //     _preset.decode(type(uint16).max, 64),
        //     _preset.decode(type(uint24).max, 80),
        //     _preset.decode(type(uint16).max, 104),
        //     _preset.decode(type(uint24).max, 120)
        // );
    }

    /// @notice Function to set the recipient of the fees. This address needs to be able to receive ERC20s
    /// @param _feeRecipient The address of the recipient
    function setFeeRecipient(address _feeRecipient) external override onlyOwner {
        _setFeeRecipient(_feeRecipient);
    }


    /// @notice Function to set the creation restriction of the Factory
    /// @param _locked If the creation is restricted (true) or not (false)
    function setFactoryLockedState(bool _locked) external override onlyOwner {
        if (creationUnlocked != _locked) revert LBFactory__FactoryLockIsAlreadyInTheSameState();
        creationUnlocked = !_locked;
        emit FactoryLockedStatusUpdated(_locked);
    }

    /// @notice Function to add an asset to the whitelist of quote assets
    /// @param _quoteAsset The quote asset (e.g: AVAX, USDC...)
    function addQuoteAsset(IERC20 _quoteAsset) external override onlyOwner {
        if (!_quoteAssetWhitelist.add(address(_quoteAsset)))
            revert LBFactory__QuoteAssetAlreadyWhitelisted(_quoteAsset);

        emit QuoteAssetAdded(_quoteAsset);
    }

    /// @notice Function to remove an asset from the whitelist of quote assets
    /// @param _quoteAsset The quote asset (e.g: AVAX, USDC...)
    function removeQuoteAsset(IERC20 _quoteAsset) external override onlyOwner {
        if (!_quoteAssetWhitelist.remove(address(_quoteAsset))) revert LBFactory__QuoteAssetNotWhitelisted(_quoteAsset);

        emit QuoteAssetRemoved(_quoteAsset);
    }

    /// @notice Internal function to set the recipient of the fee
    /// @param _feeRecipient The address of the recipient
    function _setFeeRecipient(address _feeRecipient) internal {
        if (_feeRecipient == address(0)) revert LBFactory__AddressZero();

        address _oldFeeRecipient = feeRecipient;
        if (_oldFeeRecipient == _feeRecipient) revert LBFactory__SameFeeRecipient(_feeRecipient);

        feeRecipient = _feeRecipient;
        emit FeeRecipientSet(_oldFeeRecipient, _feeRecipient);
    }

    

    /// @notice Returns the LBPairInformation if it exists,
    /// if not, then the address 0 is returned. The order doesn't matter
    /// @param _tokenA The address of the first token of the pair
    /// @param _tokenB The address of the second token of the pair
    /// @return The LBPairInformation
    function _getLBPairInformation(
        IERC20 _tokenA,
        IERC20 _tokenB
    ) private view returns (LBPairInformation memory) {
        (_tokenA, _tokenB) = _sortTokens(_tokenA, _tokenB);
        return _LBPairsInfo[_tokenA][_tokenB];
    }

    /// @notice Private view function to sort 2 tokens in ascending order
    /// @param _tokenA The first token
    /// @param _tokenB The second token
    /// @return The sorted first token
    /// @return The sorted second token
    function _sortTokens(IERC20 _tokenA, IERC20 _tokenB) private pure returns (IERC20, IERC20) {
        if (_tokenA > _tokenB) (_tokenA, _tokenB) = (_tokenB, _tokenA);
        return (_tokenA, _tokenB);
    }
}
