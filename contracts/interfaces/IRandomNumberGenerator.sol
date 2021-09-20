// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

interface IRandomNumberGenerator {
    /**
     * Requests randomness
     */
    function getRandomNumber(uint256 _seed) external;

    /**
     * Views random result(uint256)
     */
    function viewRandomResult() external view returns (uint256);

    /**
     * Views random result(uint32)
     */
    function viewRandomResult32() external view returns (uint32);
}