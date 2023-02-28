// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

library PriceHelper {

    function sortDesc(uint[] memory arr) public pure returns (uint[] memory) {
        quicksort(arr, int(0), int(arr.length - 1));
        return arr;
    }

    function quicksort(uint[] memory arr, int left, int right) internal pure {
        int i = left;
        int j = right;
        if (i == j) return;
        uint pivot = arr[uint(left + (right - left) / 2)];
        while (i <= j) {
            while (arr[uint(i)] > pivot) i++;
            while (pivot > arr[uint(j)]) j--;
            if (i <= j) {
                (arr[uint(i)], arr[uint(j)]) = (arr[uint(j)], arr[uint(i)]);
                i++;
                j--;
            }
        }
        if (left < j) quicksort(arr, left, j);
        if (i < right) quicksort(arr, i, right);
    }
}