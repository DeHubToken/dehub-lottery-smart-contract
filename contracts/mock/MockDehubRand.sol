// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "hardhat/console.sol";
import "../interfaces/IDeHubRand.sol";
import "../interfaces/IDeHubRandConsumer.sol";

contract MockDehubRand is IDeHubRand {

  address public requester;
  uint256 public latestId;
  uint256 public randomResult;

  /**
	 * Requests randomness
	 */
	function getRandomNumber() external override returns (bytes32) {
    requester = msg.sender;
    latestId = IDeHubRandConsumer(requester).viewCurrentTaskId();
    randomResult = uint256(
            keccak256(
                abi.encodePacked(
                    block.timestamp + block.difficulty +
                    ((uint256(keccak256(abi.encodePacked(block.coinbase)))) / (block.timestamp)) +
                    block.gaslimit +
                    ((uint256(keccak256(abi.encodePacked(msg.sender)))) / (block.timestamp)) +
                    block.number +
                    latestId
                )
            )
        );
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
	 * Views random result
	 */
	function viewRandomResult(address _contractAddr) external view override returns (uint32) {
    require(requester == _contractAddr, "Different contract address");
    return uint32(1000000 + (randomResult % 1000000));
  }

	/**
	 * Views random result
	 */
	function viewRandomResult256(address _contractAddr) external view override returns (uint256) {
    require(requester == _contractAddr, "Different contract address");
    return randomResult;
  }
}