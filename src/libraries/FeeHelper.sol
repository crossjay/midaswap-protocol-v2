// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./Constants.sol";
import "./SafeCast.sol";

import "../interfaces/IRoyaltyEngineV1.sol";
import "./TokenHelper.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Midas 
/// @author midaswap
/// @notice Helper contract used for fees calculation
library FeeHelper {
    using SafeCast for uint256;

    using TokenHelper for IERC20;

    /// @dev Structure to store the protocol fees:
    /// - binStep: The bin step
    /// - baseFactor: The base factor
    /// - filterPeriod: The filter period, where the fees stays constant
    /// - decayPeriod: The decay period, where the fees are halved
    /// - reductionFactor: The reduction factor, used to calculate the reduction of the accumulator
    /// - variableFeeControl: The variable fee control, used to control the variable fee, can be 0 to disable them
    /// - protocolShare: The share of fees sent to protocol
    /// - maxVolatilityAccumulated: The max value of volatility accumulated
    /// - volatilityAccumulated: The value of volatility accumulated
    /// - volatilityReference: The value of volatility reference
    /// - indexRef: The index reference
    /// - time: The last time the accumulator was called

    
    function getFeeAmountFrom(uint256 _fee, uint256 _amountWithFees) internal pure returns (uint256) {
        return (_amountWithFees * _fee + Constants.PRECISION - 1) / (Constants.PRECISION);
    }

    
    function getFeeAmount(uint256 _fee, uint256 _amount) internal pure returns (uint256) {
        uint256 _denominator = Constants.PRECISION + _fee;
        return (_amount * _fee + _denominator - 1) / _denominator;
    }


    function getFeeAmountDistribution(uint256 _rateProtocol, uint256 _fees)
        internal
        pure
        returns (uint256 _feesTotal , uint256 _feesProtocol)
    {
        _feesTotal = _fees;
        // unsafe math is fine because total >= protocol
        unchecked {
            _feesProtocol = (_fees * _rateProtocol) / Constants.PRECISION;
        }
    }

    function getFeeAmountDistributionWithRoyalty(uint256 _feeBase, uint256 _rateFee , uint256 _rateProtocol , uint256 _rateRoyalty)
        internal
        pure
        returns (uint256 _feesTotal , uint256 _feesProtocol , uint256 _feesRoyalty)
    {
        unchecked {
            _feesTotal = _feeBase * _rateFee / Constants.PRECISION - 1;
            _feesProtocol = _feesTotal * _rateProtocol / Constants.PRECISION ;
            _feesRoyalty = _feeBase * _rateRoyalty / Constants.PRECISION ;
        }
    }



    
}
