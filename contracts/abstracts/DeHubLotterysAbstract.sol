// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./DeHubLotterysUpgradeable.sol";
import "../interfaces/IDeHubRand.sol";
import "../interfaces/IDeHubRandConsumer.sol";

abstract contract DeHubLotterysAbstract is
  DeHubLotterysUpgradeable,
  IDeHubRandConsumer
{
  using SafeERC20Upgradeable for IERC20Upgradeable;
  using AddressUpgradeable for address;

  // Lottery Status
  enum Status {
    Pending, // == 0
    Open, // == 1
    Close, // == 2
    Claimable, // == 3
    Burned // == 4
  }

  address public transfererAddress; // address who can tranfer
  address public teamWallet;
  address public constant DEAD_ADDRESS =
    0x000000000000000000000000000000000000dEaD;

  uint256 public currentLotteryId;
  uint256 public currentTicketId; // Ticket Id starts from 1
  uint256 public unwonPreviousPot; // Unwon prize pot in previous round

  uint256 public maxNumberTicketsPerBuyOrClaim;

  uint256 public maxPriceTicketInDehub;
  uint256 public minPriceTicketInDehub;

  uint256 public breakDownDeLottoPot;
  uint256 public breakDownDeGrandPot;
  uint256 public breakDownTeamWallet;
  uint256 public breakDownBurn;

  IERC20Upgradeable public dehubToken;

  IDeHubRand public randomGenerator;

  modifier notContract() {
    require(!msg.sender.isContract(), "Contract not allowed");
    _;
  }

  modifier onlyTransferer() {
    require(msg.sender == transfererAddress, "Transferer is required");
    _;
  }

  event Pause();
  event Unpause();

  /**
   * @notice Set transferer address
   * @param _address transferer address
   * @dev Callable by owner
   */
  function setTransfererAddress(address _address) external onlyOwner {
    transfererAddress = _address;
  }

  /**
   * @notice Set team wallet
   * @param _address team wallet
   * @dev Callable by owner
   */
  function setTeamWallet(address _address) external onlyOwner {
    teamWallet = _address;
  }

  /**
   * @notice Set random generator
   * @param _address random generator
   * @dev Callable by owner
   */
  function setRandomGenerator(IDeHubRand _address) external onlyOwner {
    randomGenerator = _address;
  }

  /**
   * @notice Set breakdown percent
   * @param _deLottoPercent DeLotto pot percent
   * @param _deGrandPercent DeGrand pot percent
   * @param _teamPercent team percent
   * @param _burnPercent burn percent
   */
  function setBreakdownPercent(
    uint256 _deLottoPercent,
    uint256 _deGrandPercent,
    uint256 _teamPercent,
    uint256 _burnPercent
  ) external onlyOwner {
    require(
      _deLottoPercent + _deGrandPercent + _teamPercent + _burnPercent == 10000,
      "Invalid percent"
    );

    breakDownDeLottoPot = _deLottoPercent;
    breakDownDeGrandPot = _deGrandPercent;
    breakDownTeamWallet = _teamPercent;
    breakDownBurn = _burnPercent;
  }

  /**
   * @notice View current lottery id
   * @return current lottery id
   * @dev Callable by users
   */
  function viewCurrentTaskId() external view override returns (uint256) {
    return currentLotteryId;
  }

  /**
   * @notice View current unwinable pot
   * @dev Callable by lottery contract
   */
  function viewLastUnwonPot() external view returns (uint256) {
    return unwonPreviousPot;
  }

  /**
   * @notice Transfers $Dehub to address
   * @param _addr destination address
   * @param _amount $Dehub token amount
   * @dev Callable by transferer
   */
  function transferTo(address _addr, uint256 _amount)
    external
    onlyTransferer
  {
    dehubToken.safeTransfer(_addr, _amount);
  }

  /**
   * @notice Triggers stopped state
   * @dev Only possible when contract not paused.
   */
  function pause() external onlyOwner whenNotPaused {
    _pause();
    emit Pause();
  }

  /**
   * @notice Returns to normal state
   * @dev Only possible when contract is paused
   */
  function unpause() external onlyOwner whenPaused {
    _unpause();
    emit Unpause();
  }
}