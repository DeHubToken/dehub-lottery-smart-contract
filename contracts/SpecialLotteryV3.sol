// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "hardhat/console.sol";
import "./SpecialLotteryV2.sol";

/**
 * @dev V3 upgrade template. Use this if update is needed in the future.
 */
contract SpecialLotteryV3 is SpecialLotteryV2 {
  /**
   * @dev Must call this jsut after the upgrade deployement, to update state
   * variables and execute other upgrade logic.
   * Ref: https://github.com/OpenZeppelin/openzeppelin-upgrades/issues/62
   */
  function upgradeToV3() public {
    require(version < 3, "SpecialLottery: Already upgraded to version 3");
    version = 3;
    console.log("v", version);
  }
}
