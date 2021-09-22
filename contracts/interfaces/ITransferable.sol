// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

interface ITransferable {

  /**
   * @notice Transfer token to given address
   * @param _addr destination address
   * @param _amount amount of token to transfer
   */
  function transferTo(
    address _addr,
    uint256 _amount
  ) external;
}