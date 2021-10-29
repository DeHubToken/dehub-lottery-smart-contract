// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "hardhat/console.sol";
import "../interfaces/IDeHubRand.sol";
import "../interfaces/IDeHubRandConsumer.sol";

contract MockDehubFixedRand is IDeHubRand {

  address public requester;
  uint256 public latestId;
  uint256 public randomResult;

  /**
   * Set random result by outside
   */
  function setRandomResult(uint256 _randomResult) external {
    randomResult = _randomResult;
  }

  /**
	 * Requests randomness
	 */
	function getRandomNumber() external override returns (bytes32) {
    requester = msg.sender;
    latestId = IDeHubRandConsumer(requester).viewCurrentTaskId();
    return 0;
  }

	/**
	 * @notice View latest id for a requesting contract
	 */
	function viewLatestId(address _contractAddr) external view override returns (uint256) {
    require(requester == _contractAddr, "Different contract address");
    return latestId;
  }

	/**
	 * @notice Views random result
	 */
	function viewRandomResult(address _contractAddr) external view override returns (uint32) {
    require(requester == _contractAddr, "Different contract address");
    return uint32(1000000 + (randomResult % 1000000));
  }

	/**
	 * @notice Views random result
	 */
	function viewRandomResult256(address _contractAddr) external view override returns (uint256) {
    require(requester == _contractAddr, "Different contract address");
    return randomResult;
  }
}