// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "hardhat/console.sol";
import "./SpecialLotteryV3.sol";

/**
 * @dev V4 upgrade template. Use this if update is needed in the future.
 */
contract SpecialLotteryV4 is SpecialLotteryV3 {
  /**
   * @dev Must call this jsut after the upgrade deployement, to update state
   * variables and execute other upgrade logic.
   * Ref: https://github.com/OpenZeppelin/openzeppelin-upgrades/issues/62
   */
  function upgradeToV4() public {
    require(version < 4, "SpecialLottery: Already upgraded to version 4");
    version = 4;
    console.log("v", version);
  }
}
