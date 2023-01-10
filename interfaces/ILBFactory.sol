// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./ILBPair.sol";
import "./IPendingOwnable.sol";

/// @title Liquidity Book Factory Interface
/// @author Trader Joe
/// @notice Required interface of LBFactory contract
interface ILBFactory is IPendingOwnable {
    /// @dev Structure to store the LBPair information, such as:
    /// - binStep: The bin step of the LBPair
    /// - LBPair: The address of the LBPair
    /// - createdByOwner: Whether the pair was created by the owner of the factory
    /// - ignoredForRouting: Whether the pair is ignored for routing or not. An ignored pair will not be explored during routes finding
    struct LBPairInformation {
        ILBPair LBPair;
        bool createdByOwner;
    }

    event LBPairCreated(
        IERC20 indexed tokenX,
        IERC20 indexed tokenY,
        ILBPair LBPair,
        uint256 pid
    );

    event FeeRecipientSet(address oldRecipient, address newRecipient);

    event FlashLoanFeeSet(uint256 oldFlashLoanFee, uint256 newFlashLoanFee);

    event FeeParametersSet(
        address indexed sender,
        ILBPair indexed LBPair,
        uint256 baseFactor,
        uint256 filterPeriod,
        uint256 decayPeriod,
        uint256 reductionFactor,
        uint256 variableFeeControl,
        uint256 protocolShare,
        uint256 maxVolatilityAccumulated
    );

    event FactoryLockedStatusUpdated(bool unlocked);

    event LBPairImplementationSet(address oldLBPairImplementation, address LBPairImplementation);

    event LBPairIgnoredStateChanged(ILBPair indexed LBPair, bool ignored);

    event PresetSet(
        uint256 baseFactor,
        uint256 filterPeriod,
        uint256 decayPeriod,
        uint256 reductionFactor,
        uint256 variableFeeControl,
        uint256 protocolShare,
        uint256 maxVolatilityAccumulated,
        uint256 sampleLifetime
    );

    event PresetRemoved();

    event QuoteAssetAdded(IERC20 indexed quoteAsset);

    event QuoteAssetRemoved(IERC20 indexed quoteAsset);

    function MAX_FEE() external pure returns (uint256);

    // function MIN_BIN_STEP() external pure returns (uint256);

    // function MAX_BIN_STEP() external pure returns (uint256);

    // function MAX_PROTOCOL_SHARE() external pure returns (uint256);

    function LBPairImplementation() external view returns (address);

    function getNumberOfQuoteAssets() external view returns (uint256);

    function getQuoteAsset(uint256 index) external view returns (IERC20);

    function isQuoteAsset(IERC20 token) external view returns (bool);

    function feeRecipient() external view returns (address);

    function flashLoanFee() external view returns (uint256);

    function creationUnlocked() external view returns (bool);

    function allLBPairs(uint256 id) external returns (ILBPair);

    function getNumberOfLBPairs() external view returns (uint256);

    function getLBPairInformation(
        IERC20 tokenX,
        IERC20 tokenY
    ) external view returns (LBPairInformation memory);

    // function getPreset()
    //     external
    //     view
    //     returns (
    //         uint256 baseFactor,
    //         uint256 filterPeriod,
    //         uint256 decayPeriod,
    //         uint256 reductionFactor,
    //         uint256 variableFeeControl,
    //         uint256 protocolShare,
    //         uint256 maxAccumulator,
    //         uint256 sampleLifetime
    //     );

    // function getAllBinSteps() external view;

    // function getAllLBPairs(IERC20 tokenX, IERC20 tokenY)
    //     external
    //     view
    //     returns (LBPairInformation[] memory LBPairsBinStep);

    function setLBPairImplementation(address LBPairImplementation) external;

    function createLBPair(
        IERC20 tokenX,
        IERC20 tokenY,
        uint24 activeId
    ) external returns (ILBPair pair);

    // function setLBPairIgnored(
    //     IERC20 tokenX,
    //     IERC20 tokenY,

    //     bool ignored
    // ) external;

    // function setPreset(

    //     uint16 baseFactor,
    //     uint16 filterPeriod,
    //     uint16 decayPeriod,
    //     uint16 reductionFactor,
    //     uint24 variableFeeControl,
    //     uint16 protocolShare,
    //     uint24 maxVolatilityAccumulated,
    //     uint16 sampleLifetime
    // ) external;

    // function removePreset() external;

    // function setFeesParametersOnPair(
    //     IERC20 tokenX,
    //     IERC20 tokenY,
    //     uint16 baseFactor,
    //     uint16 filterPeriod,
    //     uint16 decayPeriod,
    //     uint16 reductionFactor,
    //     uint24 variableFeeControl,
    //     uint16 protocolShare,
    //     uint24 maxVolatilityAccumulated
    // ) external;

    function setFeeRecipient(address feeRecipient) external;

    // function setFlashLoanFee(uint256 flashLoanFee) external;

    function setFactoryLockedState(bool locked) external;

    function addQuoteAsset(IERC20 quoteAsset) external;

    function removeQuoteAsset(IERC20 quoteAsset) external;

    // function forceDecay(ILBPair LBPair) external;
}
