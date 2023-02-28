// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./BinHelper.sol";
import "./Constants.sol";
import "./FeeHelper.sol";
import "./Math512Bits.sol";

import "../interfaces/IMidasPair721.sol";


/// @title Midas 
/// @author midaswap
/// @notice Helper contract used for calculating swaps, fees and reserves changes
library SwapHelper {
    using Math512Bits for uint256;


   
    // function getAmounts(
    //     ILBPair.Bin memory bin,
    //     FeeHelper.FeeParameters memory fp,
    //     uint256 activeId,
    //     bool swapForY,
    //     uint256 amountIn
    // )
    //     internal
    //     pure
    //     returns (
    //         uint256 amountInToBin,
    //         uint256 amountOutOfBin,
    //         FeeHelper.FeesDistribution memory fees
    //     )
    // {
    //     uint256 _price = BinHelper.getPriceFromId(activeId);

    //     uint256 _reserve;
    //     uint256 _maxAmountInToBin;

    //     if (swapForY) {
    //         _reserve = bin.reserveY;
    //         _maxAmountInToBin = _reserve.shiftDivRoundUp(Constants.SCALE_OFFSET, _price);
    //         fees = fp.getFeeAmountDistribution(fp.getFeeAmountFrom(_reserve));
    //         if (_maxAmountInToBin <= amountIn){
    //             amountInToBin = _maxAmountInToBin;
    //             amountOutOfBin = _reserve;
    //         }else{
    //             amountInToBin = amountIn;
    //             amountOutOfBin = _price.mulShiftRoundDown(amountInToBin, Constants.SCALE_OFFSET);
    //             fees = fp.getFeeAmountDistribution(fp.getFeeAmountFrom(amountOutOfBin));
    //         }
    //         // Safety check in case rounding returns a higher value than expected
    //         if (amountOutOfBin > _reserve) amountOutOfBin = _reserve;
    //     }else{
    //         _reserve = bin.reserveX;
    //         _maxAmountInToBin = _price.mulShiftRoundUp(_reserve, Constants.SCALE_OFFSET);
    //         fees = fp.getFeeAmountDistribution(fp.getFeeAmount(_maxAmountInToBin));
    //         if (_maxAmountInToBin + fees.total <= amountIn) {
    //             amountInToBin = _maxAmountInToBin;
    //             amountOutOfBin = _reserve;
    //         }else{
    //             fees = fp.getFeeAmountDistribution(fp.getFeeAmountFrom(amountIn));
    //             amountInToBin = amountIn - fees.total;
    //             amountOutOfBin = amountInToBin.shiftDivRoundDown(Constants.SCALE_OFFSET, _price);
    //         }
    //         // Safety check in case rounding returns a higher value than expected
    //         if (amountOutOfBin > _reserve) amountOutOfBin = _reserve;
    //     }

        // if (swapForY) {
        //     _reserve = bin.reserveY;
        //     _maxAmountInToBin = _reserve.shiftDivRoundUp(Constants.SCALE_OFFSET, _price);
        // } else {
        //     _reserve = bin.reserveX;
        //     _maxAmountInToBin = _price.mulShiftRoundUp(_reserve, Constants.SCALE_OFFSET);
        // }

        // fp.updateVolatilityAccumulated(activeId);
        // fees = fp.getFeeAmountDistribution(fp.getFeeAmount(_maxAmountInToBin));

        // if (_maxAmountInToBin + fees.total <= amountIn) {
        //     amountInToBin = _maxAmountInToBin;
        //     amountOutOfBin = _reserve;
        // } else {
        //     fees = fp.getFeeAmountDistribution(fp.getFeeAmountFrom(amountIn));
        //     amountInToBin = amountIn - fees.total;
        //     amountOutOfBin = swapForY
        //         ? _price.mulShiftRoundDown(amountInToBin, Constants.SCALE_OFFSET)
        //         : amountInToBin.shiftDivRoundDown(Constants.SCALE_OFFSET, _price);
        //     // Safety check in case rounding returns a higher value than expected
        //     if (amountOutOfBin > _reserve) amountOutOfBin = _reserve;
        // }

    

    function updateFees(
        IMidasPair721.PairInformation memory pair,
        uint256 _feesTotal,
        uint256 _feesProtocol
    ) internal pure {
        pair.feesTotal += _feesTotal;
        // unsafe math is fine because total >= protocol
        unchecked {
            pair.feesProtocol += _feesProtocol;
        }
    }

    // function updateFees(
    //     IMidasPair1155.PairInformation memory pair,
    //     uint256 _feesTotal,
    //     uint256 _feesProtocol
    // ) internal pure {
    //     pair.feesTotal += _feesTotal;
    //     // unsafe math is fine because total >= protocol
    //     unchecked {
    //         pair.feesProtocol += _feesProtocol;
    //     }
    // }

    /// @notice Update reserves
    /// @param bin The bin information
    /// @param pair The pair information
    /// @param swapForY whether the token sent was Y (true) or X (false)
    /// @param amountInToBin The amount of token that is added to the bin without fees
    /// @param amountOutOfBin The amount of token that is removed from the bin
    function updateReserves(
        IMidasPair721.PairInformation memory pair,
        uint256[2] memory bin,
        bool swapForY,
        uint256 amountInToBin,
        uint256 amountOutOfBin
    ) internal pure {
        if (swapForY) {
            bin[0] += amountInToBin;

            unchecked {
                bin[1] -= amountOutOfBin;
                pair.reserveX += uint136(amountInToBin);
                pair.reserveY -= uint136(amountOutOfBin);
            }
        } else {
            bin[1] += amountInToBin;

            unchecked {
                bin[0] -= amountOutOfBin;
                pair.reserveX -= uint136(amountOutOfBin);
                pair.reserveY += uint136(amountInToBin);
            }
        }
    }



    // function updateReserves(
    //     IMidasPair1155.PairInformation memory pair,
    //     uint256[2] memory bin ,
    //     bool swapForY,
    //     uint256 amountInToBin,
    //     uint256 amountOutOfBin
    // ) internal pure {
    //     if (swapForY) {
    //         bin[0] += amountInToBin;

    //         unchecked {
    //             bin[1] -= amountOutOfBin;
    //             pair.reserveX += uint136(amountInToBin);
    //             pair.reserveY -= uint136(amountOutOfBin);
    //         }
    //     } else {
    //         bin[1] += amountInToBin;

    //         unchecked {
    //             bin[0] -= amountOutOfBin;
    //             pair.reserveX -= uint136(amountOutOfBin);
    //             pair.reserveY += uint136(amountInToBin);
    //         }
    //     }
    // }


    function updateRoyaltyFees(
        IMidasPair721.PairInformation memory pair,
        uint256 _fees
    ) internal pure {
        unchecked{
            pair.feesRoyalty += _fees;
        }
    }
}
