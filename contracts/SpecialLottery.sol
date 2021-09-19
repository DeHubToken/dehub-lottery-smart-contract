// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IRandomNumberGenerator.sol";

contract StandardLottery is Ownable, ReentrancyGuard {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  enum Status {
    Pending,
    Open,
    Close,
    Claimable
  }

  struct Lottery {
    Status status;
    uint256 startTime;
    uint256 endTime;
    uint256 ticketRate; // $Dehub price per ticket
    uint256 amountCollectedToken; // collected $Dehub token amount
    uint256 firstTicketId;
    uint256 firstTicketIdNextLottery;
    uint256 finalNumber;
  }

  address public operatorAddress; // Scheduler wallet address
  address public deLottoAddress; // Address to StandardLottery
  address public teamWallet;
  address public immutable deadAddress = 0x000000000000000000000000000000000000dEaD;

  uint256 public currentLotteryId;
  uint256 public currentTicketId;

  uint256 public maxNumberTicketsPerBuyOrClaim;

  uint256 public maxPriceTicketInDehub = 50 ether;
  uint256 public minPriceTicketInDehub = 0.005 ether;

  uint256 public maxNumberPickWinners;
  uint256 public breakDownDeLottoPot = 7000; // 70%
  uint256 public breakDownTeamWallet = 2000; // 20%
  uint256 public breakDownBurn = 1000; // 10%

  IERC20 public dehubToken;

  IRandomNumberGenerator public randomGenerator;

  // <lotteryId, Lottery>
  mapping(uint256 => Lottery) _lotteries;
  // <ticketId, user address>
  mapping(uint256 => address) _tickets;
  // <ticketId, bool>
  mapping(uint256 => bool) _claimed;
  // <user address, <lotteryId, ticketId[]>>
  mapping(address => mapping(uint256 => uint256[])) _userTicketIdsPerLotteryId;

  uint256 public constant MIN_LENGTH_LOTTERY = 6 hours - 5 minutes; // 6 hours
  uint256 public constant MAX_LENGTH_LOTTERY = 6 days + 5 minutes; // 6 days
  uint256 public constant MAX_DELOTTO_SECOND_TICKETS = 100;

  modifier onlyOperator() {
    require(msg.sender == operatorAddress, "Operator is required");
    _;
  }

  modifier notContract() {
    require(!_isContract(msg.sender), "Contract not allowed");
    require(msg.sender == tx.origin, "Proxy contract not allowed");
    _;
  }

  event LotteryOpen(
    uint256 indexed lotteryId,
    uint256 startTime,
    uint256 endTime,
    uint256 priceTicketInDehub,
    uint256 firstTicketId
  );
  event LotteryClose(uint256 indexed lotteryId, uint256 firstTicketIdNextLottery);
  event TicketsPurchase(address indexed buyer, uint256 indexed lotteryId, uint256 numberTickets);
  event TicketsClaim(address indexed claimer, uint256 amount, uint256 indexed lotteryId, uint256 numberTickets);

  constructor(
    IERC20 _dehubToken,
    IRandomNumberGenerator _randomGenerator
  ) {
    dehubToken = _dehubToken;
    randomGenerator = _randomGenerator;
  }

  /**
   * @notice Buys tickets for the current lottery staking $Dehub
   * @param _lotteryId lottery id
   * @param _ticketCount purchased ticket count 
   * @dev Callable by users
   */
  function buyTickets(
    uint256 _lotteryId,
    uint256 _ticketCount
  ) external notContract nonReentrant {
    require(_ticketCount <= maxNumberTicketsPerBuyOrClaim, "Too many tickets");

    require(_lotteries[_lotteryId].status == Status.Open, "Lottery is not open");
    require(block.timestamp < _lotteries[_lotteryId].endTime, "Lottery is over");

    // Calculate number of $Dehub to breakdown
    uint256 amountDehubToTransfer = _calculateTotalPriceForBulkTickets(
      _lotteries[_lotteryId].ticketRate,
      _ticketCount
    );

    uint256 deLottoAmount = amountDehubToTransfer.mul(breakDownDeLottoPot).div(10000);
    uint256 teamAmount = amountDehubToTransfer.mul(breakDownTeamWallet).div(10000);
    dehubToken.safeTransferFrom(address(msg.sender), deLottoAddress, deLottoAmount);
    dehubToken.safeTransferFrom(address(msg.sender), teamWallet, teamAmount);
    dehubToken.safeTransferFrom(address(msg.sender), deadAddress,
      amountDehubToTransfer.sub(deLottoAmount).sub(teamAmount));

    _lotteries[_lotteryId].amountCollectedToken = amountDehubToTransfer;

    for (uint256 i = 0; i < _ticketCount; i++) {
      _tickets[currentTicketId] = msg.sender;

      _userTicketIdsPerLotteryId[msg.sender][_lotteryId].push(currentTicketId);

      // increase ticket serial number
      currentTicketId++;
    }

    emit TicketsPurchase(msg.sender, _lotteryId, _ticketCount);
  }

  /**
   * @notice Claims a set of guaranteed winning tickets for the second stage of DeLotto lottery
   * @param _lotteryId lottery id
   * @param _ticketIds array of ticket ids
   * @dev Callable by users
   */
  function claimTickets(
    uint256 _lotteryId,
    uint256[] calldata _ticketIds
  ) external notContract nonReentrant {
    require(_ticketIds.length != 0, "Length must be >0");
    require(_ticketIds.length <= maxNumberTicketsPerBuyOrClaim, "Too many tickets");
    require(_lotteries[_lotteryId].status == Status.Claimable, "Lottery not claimable");

    // Initializes the rewardInDehubToTransfer
    uint256 rewardInDehubToTransfer;

    for (uint256 i = 0; i < _ticketIds.length; i++) {
      uint256 thisTicketId = _ticketIds[i];

      require(_lotteries[_lotteryId].firstTicketIdNextLottery > thisTicketId, "TicketId too high");
      require(_lotteries[_lotteryId].firstTicketId <= thisTicketId, "TicketId too low");
      require(msg.sender == _tickets[thisTicketId], "Not the owner");

      // Update the lottery ticket owner to 0x address
      _tickets[thisTicketId] = address(0);

      // Calculate reward of DeLotto second stage
      uint256 rewardForTicketId = _calculateRewardsForTicketId(_lotteryId, thisTicketId);

      // Increment the reward to transfer
      rewardInDehubToTransfer += rewardForTicketId;
    }

    // Transfer money to msg.sender
    dehubToken.safeTransfer(msg.sender, rewardInDehubToTransfer);

    emit TicketsClaim(msg.sender, rewardInDehubToTransfer, _lotteryId, _ticketIds.length);
  }

  /**
   * @notice Close the lottery
   * @param _lotteryId lottery id
   * @dev Callabel by operator
   */
  function closeLottery(uint256 _lotteryId) external onlyOperator nonReentrant {
    require(_lotteries[_lotteryId].status == Status.Open, "Lottery not open");
    require(block.timestamp > _lotteries[_lotteryId].endTime, "Lottery not over");
    _lotteries[_lotteryId].firstTicketIdNextLottery = currentTicketId;

    // Request a random number from the generator based on a seed
    randomGenerator.getRandomNumber(uint256(keccak256(abi.encodePacked(_lotteryId, currentTicketId))));

    _lotteries[_lotteryId].status = Status.Close;

    emit LotteryClose(_lotteryId, currentTicketId);
  }

  /**
   * @notice Picks the number of winners by the DeHub team. Only used for the DeGrand lottery
   * @param _lotteryId lottery id
   * @param _maxNumberPickWinners maximum number of picking winners
   * @dev Callabel by operator
   */
  function pickDeGrandWinners(
    uint256 _lotteryId,
    uint256 _maxNumberPickWinners
  ) external onlyOwner nonReentrant {

  }

  /**
   * @notice Picks the number of winners. Only used for the DeLotto second stage
   * @param _lotteryId lottery id
   * @dev Callable by operator
   */
  function pickAwardWinners(uint256 _lotteryId) external onlyOwner nonReentrant {
    
  }

  /**
   * @notice Start the lottery
   * @param _endTime end time of the lottery
   * @param _ticketRate price of a ticket in $Dehub
   * @dev Callable by operator
   */
  function startLottery(
    uint256 _endTime,
    uint256 _ticketRate
  ) external onlyOperator {
    require(
      (currentLotteryId == 0) || (_lotteries[currentLotteryId].status == Status.Claimable),
      "Not time to start lottery"
    );
    require(
      ((_endTime - block.timestamp) > MIN_LENGTH_LOTTERY) && ((_endTime - block.timestamp) < MAX_LENGTH_LOTTERY),
      "Lottery length outside of range"
    );
    require(
      (_ticketRate >= minPriceTicketInDehub) && (_ticketRate <= maxPriceTicketInDehub),
      "Outside of limits"
    );

    currentLotteryId++;

    _lotteries[currentLotteryId] = Lottery({
      status: Status.Open,
      startTime: block.timestamp,
      endTime: _endTime,
      ticketRate: _ticketRate,
      amountCollectedToken: 0,
      firstTicketId: currentTicketId,
      firstTicketIdNextLottery: currentTicketId,
      finalNumber: 0
    });

    emit LotteryOpen(
      currentLotteryId,
      block.timestamp,
      _endTime,
      _ticketRate,
      currentTicketId
    );
  }

  /**
   * @notice Transfers $Dehub to address
   * @param _addr destination address
   * @param _amount $Dehub token amount
   * @dev Callable by owner
   */
  function transferTo(
    address _addr,
    uint256 _amount
  ) external onlyOwner {
    dehubToken.safeTransfer(_addr, _amount);
  }

  /**
   * @notice Set $Dehub price ticket upper/lower limit
   * @dev Only callable by owner
   * @param _minPriceTicketInDehub: minimum price of a ticket in $Dehub
   * @param _maxPriceTicketInDehub: maximum price of a ticket in $Dehub
   */
  function setMinAndMaxTicketPriceInDehub(
    uint256 _minPriceTicketInDehub,
    uint256 _maxPriceTicketInDehub
  ) external onlyOwner {
    require(_minPriceTicketInDehub <= _maxPriceTicketInDehub, "minPrice must be < maxPrice");

    minPriceTicketInDehub = _minPriceTicketInDehub;
    maxPriceTicketInDehub = _maxPriceTicketInDehub;
  }

  /**
   * @notice Set the maximum number of tickets to buy or claim
   * @param _maxNumberTicketsPerBuy maximum number of tickets to buy or claim
   * @dev Callable by owner
   */
  function setMaxNumberTicketsPerBuy(uint256 _maxNumberTicketsPerBuy) external onlyOwner {
    require(_maxNumberTicketsPerBuy != 0, "Must be > 0");
    maxNumberTicketsPerBuyOrClaim = _maxNumberTicketsPerBuy;
  }

  /**
   * @notice Set operator address
   * @param _address operator address
   * @dev Callable by owner
   */
  function setOperatorAddress(address _address) external onlyOwner {
    operatorAddress = _address;
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
  function setRandomGenerator(IRandomNumberGenerator _address) external onlyOwner {
    randomGenerator = _address;
  }

  /**
   * @notice Set breakdown percent
   * @param _deLottoPercent DeLotto pot percent
   * @param _teamPercent team percent
   * @param _burnPercent burn percent
   */
  function setBreakdownPercent(
    uint256 _deLottoPercent,
    uint256 _teamPercent,
    uint256 _burnPercent
  ) external onlyOwner {
    require(_deLottoPercent + _teamPercent + _burnPercent == 10000, "Invalid percent");

    breakDownDeLottoPot = _deLottoPercent;
    breakDownTeamWallet = _teamPercent;
    breakDownBurn = _burnPercent;
  }

  /**
   * @notice View current lottery id
   * @return current lottery id
   * @dev Callable by users
   */
  function viewCurrentLotteryId() external view returns (uint256) {
    return currentLotteryId;
  }

  /**
   * @notice View lottery information
   * @param _lotteryId lottery id
   * @dev Callable by users
   */
  function viewLottery(uint256 _lotteryId) external view returns (Lottery memory) {
    return _lotteries[_lotteryId];
  }

  /**
   * @notice View rewards for ticket id
   * @param _lotteryId lottery id
   * @param _ticketIds array of ticket ids
   */
  function viewRewardsForTicketId(
    uint256 _lotteryId,
    uint256[] calldata _ticketIds
  ) external view returns (uint256) {
    // Check lottery is in claimable status
    if (_lotteries[_lotteryId].status != Status.Claimable) {
      return 0;
    }
    require(_ticketIds.length <= maxNumberTicketsPerBuyOrClaim, "Too many tickets");

    uint256 rewards;
    for (uint256 i = 0; i < _ticketIds.length; i++) {
      if (_tickets[_ticketIds[i]] == address(0)) {
        continue;
      }

      // Calculate reward of DeLotto second stage
      uint256 rewardForTicketId = _calculateRewardsForTicketId(_lotteryId, _ticketIds[i]);

      // Increment the reward to transfer
      rewards += rewardForTicketId;
    }
    return rewards;
  }

  /**
   * @notice View user ticket ids, numbers, and statuses of user for a given lottery
   * @param _user user address
   * @param _lotteryId lottery Id
   * @param _cursor cursor to start where to retrieve the tickets
   * @param _size the number of tickets to retrieve
   */
  function viewUserInfoForLotteryId(
    address _user,
    uint256 _lotteryId,
    uint256 _cursor,
    uint256 _size
  ) external view returns (
    uint256[] memory, // array of ticket ids
    bool[] memory, // array of claimed status
    uint256 // next cursor
  ) {
    uint256 length = _size;
    uint256 numberTicketsBoughtAtLotteryId = _userTicketIdsPerLotteryId[_user][_lotteryId].length;

    if (length > (numberTicketsBoughtAtLotteryId - _cursor)) {
      length = numberTicketsBoughtAtLotteryId - _cursor;
    }

    uint256[] memory lotteryTicketIds = new uint256[](length);
    bool[] memory ticketStatuses = new bool[](length);

    for (uint256 i = 0; i < length; i++) {
      lotteryTicketIds[i] = _userTicketIdsPerLotteryId[_user][_lotteryId][i + _cursor];

      // True = ticket claimed
      if (_tickets[lotteryTicketIds[i]] == address(0)) {
        ticketStatuses[i] = true;
      } else {
        // ticket not claimed (includes the ones that cannot be claimed)
        ticketStatuses[i] = false;
      }
    }

    return (lotteryTicketIds, ticketStatuses, _cursor + length);
  }

  /**
   * @notice Get nth number which has limit in random number
   * @param _random random number
   * @param _index index
   * @param _limit limit of each number
   * @return nth number
   */
  function _pickAwardNumberInRandom(
    uint256 _random,
    uint256 _index,
    uint256 _limit
  ) internal pure returns (uint256) {
    require(_index >= 0 && _index < 128, "Maximum index limit is 128");
    require(_limit > 0, "Non-zero limit in Random");

    return (_random >> (2 * _index)) % _limit;
  }

  /**
   * @notice Calculate rewards for a given ticket
   * @param _lotteryId: lottery id
   * @param _ticketId: ticket id
   * @return lottery reward
   */
  function _calculateRewardsForTicketId(
    uint256 _lotteryId,
    uint256 _ticketId
  ) internal view returns (uint256) {
    // Retrieve the winning number combination
    uint256 finalNumber = _lotteries[_lotteryId].finalNumber;
    uint256 ticketCount = _lotteries[_lotteryId].firstTicketIdNextLottery - _lotteries[_lotteryId].firstTicketId;

    if (ticketCount >= MAX_DELOTTO_SECOND_TICKETS) {
      // if bought over 100 tickets, pick 100 ticket as random
      uint256 ticketIndex = _ticketId - _lotteries[_lotteryId].firstTicketId;
      uint256 pickNumber = _pickAwardNumberInRandom(finalNumber,
        ticketIndex,
        _lotteries[_lotteryId].firstTicketIdNextLottery - _lotteries[_lotteryId].firstTicketId
      );
      if (pickNumber + _lotteries[_lotteryId].firstTicketId == _ticketId) {
        return dehubToken.balanceOf(address(deLottoAddress)).div(100); // every ticket has 1% of unwon pot
      }
      return 0;
    }
    return dehubToken.balanceOf(address(deLottoAddress)).div(100); // every ticket has 1% of unwon pot
  }

  /**
   * @notice Calculate final price for bulk tickets
   * @param _ticketRate price of a ticket in $Dehub
   * @param _ticketCount: count of tickets purchased
   */
  function _calculateTotalPriceForBulkTickets(
    uint256 _ticketRate,
    uint256 _ticketCount
  ) internal pure returns (uint256) {
    return _ticketRate * _ticketCount;
  }

  /**
    * @notice Checks if address is a contract
    * @dev It prevents contract from being targetted
    */
  function _isContract(address addr) internal view returns (bool) {
    uint256 size;
    assembly {
      size := extcodesize(addr)
    }
    return size > 0;
  }
}