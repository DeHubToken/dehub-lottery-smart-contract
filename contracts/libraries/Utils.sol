// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

library Utils {

  /**
   * @notice Get nth number which has limit in random number
   * @param _random random number
   * @param _index index
   * @param _limit limit of each number
   * @return nth number
   */
  function pickNumberInRandom(
    uint256 _random,
    uint256 _index,
    uint256 _limit
  ) internal pure returns (uint256) {
    require(_index >= 0 && _index < 128, "Maximum index limit is 128");
    require(_limit > 0, "Non-zero limit in Random");

    return (_random >> (2 * _index)) % _limit;
  }
}