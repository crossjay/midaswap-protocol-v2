// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

library PositionHelper {
    function _checkBinSequence(
        uint24[] memory _binIds
    ) internal pure returns (bool) {
        if (_binIds.length < 2) {
            return true;
        }
        uint24 commonDiff = _binIds[1] - _binIds[0];
        if (commonDiff < 0) {
            return false;
        }
        for (uint i = 2; i < _binIds.length; i++) {
            if (_binIds[i] - _binIds[i - 1] != commonDiff) {
                return false;
            }
        }
        return true;
    }

    function _getBinStep(
        uint24[] memory _binIds
    ) internal pure returns (uint24 commonDiff) {
        if (_binIds.length < 2) {
            commonDiff = 0;
        } else {
            commonDiff = _binIds[1] - _binIds[0];
        }     
    }

    function _findIndex(
        uint256[] memory arr, 
        uint256 target
    ) internal pure returns (uint256) {
        for (uint i = 0; i < arr.length; i++) {
            if (arr[i] == target) {
                return i;
            }
        }
        return type(uint256).max;
    }

    function _findNonZeroIndex(
        uint256[] memory arr
    ) internal pure returns (uint256) {
        for (uint i = 0; i < arr.length; i++) {
            if (arr[i] != 0 && arr[i] >= 1) {
                return i;
            }
        }
        return type(uint256).max;
    }

    function _removeItem(
        uint256[] memory arr, 
        uint256 indexToRemove
    ) internal pure returns (uint256[] memory) {
        uint256[] memory newArr = new uint256[](arr.length - 1);
        uint256 newIndex = 0;
        for (uint i = 0; i < arr.length; i++) {
            if (i != indexToRemove) {
                newArr[newIndex] = arr[i];
                newIndex++;
            }
        }
        return newArr;
    }

} 