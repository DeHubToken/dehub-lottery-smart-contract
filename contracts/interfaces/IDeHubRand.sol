// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IDeHubRand {
	/**
	 * Requests randomness
	 */
	function getRandomNumber() external returns (bytes32);

	/**
	 * @notice View latest id for a requesting contract
	 */
	function viewLatestId(address _contractAddr) external view returns (uint256);

	/**
	 * Views random result
	 */
	function viewRandomResult(address _contractAddr) external view returns (uint32);

	/**
	 * Views random result
	 */
	function viewRandomResult256(address _contractAddr) external view returns (uint256);
}