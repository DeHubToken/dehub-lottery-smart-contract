// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "hardhat/console.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

abstract contract DeHubLotterysUpgradeable is
	Initializable,
	OwnableUpgradeable,
	ReentrancyGuardUpgradeable,
	PausableUpgradeable,
	UUPSUpgradeable
{
	using SafeERC20Upgradeable for IERC20Upgradeable;
	using AddressUpgradeable for address;

	uint public version;

	function initialize() public initializer {
		__Ownable_init();
		__ReentrancyGuard_init();
		__Pausable_init();
		__UUPSUpgradeable_init();
		version = 1;
		console.log('v', version);
	}

	function _authorizeUpgrade(address newImplementation)
		internal
		onlyOwner
		override
	{}
}