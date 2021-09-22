// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IDeHubRandConsumer {
	/**
	 * @notice View current consumer task id. 
	 * Each time a consumer requests the random number, it generates a unique
	 * id which helps to link and verify consumer and its task with the random
	 * number resolved.
	 */
	function viewCurrentTaskId() external returns (uint256);
}