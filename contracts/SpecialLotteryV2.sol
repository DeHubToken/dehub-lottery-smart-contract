// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "hardhat/console.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "./abstracts/DeHubLotterysAbstract.sol";
import "./libraries/Utils.sol";

/**
 * @dev V2 upgrade template. Use this if update is needed in the future.
 */
contract SpecialLotteryV2 is DeHubLotterysAbstract {
  using SafeMathUpgradeable for uint256;
  using SafeERC20Upgradeable for IERC20Upgradeable;
  using AddressUpgradeable for address;

  struct Lottery {
    Status deLottoStatus; // Status for DeLotto second stage
    Status deGrandStatus; // Status for DeGrand stage
    uint256 startTime;
    uint256 endTime; // Close time for DeLotto second stage
    uint256 ticketRate; // $Dehub price per ticket
    uint256 unwonPreviousPot; // unwon pot in previous round
    uint256 amountCollectedToken; // Collected $Dehub token amount which transfered to DeLotto
    uint256 firstTicketId;
    uint256 firstTicketIdNextLottery;
    uint256 deLottoFinalNumber; // Final number for DeLotto second stage, TODO, will be removed on mainnet
    uint256 deGrandMaximumWinners; // Maximum number of picking winners in DeGrand stage
    uint256 deGrandFinalNumber; // Final number for DeGrand stage, TODO, will be removed on mainnet
  }

  struct DeGrandPrize {
    uint256 drawTime; // Draw time for DeGrand stage
    string title;
    string subtitle;
    string description; // (optional)
    string ctaUrl; // URL link to more info (optional)
    string imageUrl; // URL link to a graphic image (optional)
    uint256 maxWinnerCount; // how many users will get this prize
    bool picked; // If picked, true
  }

  struct DeGrandWinner {
    address user;
    uint256 ticketId;
  }

  address public operatorAddress; // Scheduler wallet address
  DeHubLotterysAbstract public deLottoAddress; // Address to StandardLottery

  // <lotteryId, Lottery>
  mapping(uint256 => Lottery) private _lotteries;
  // <lotteryId, <picked ticket id, bool>: Used in DeLotto second stage which has more than 100 tickets
  mapping(uint256 => mapping(uint256 => bool)) private _deLottoWinnerTicketIds;
  // <lotteryId, <picked ticket id, bool>>
  mapping(uint256 => mapping(uint256 => bool)) private _deGrandWinnerTicketIds;
  // <month index, DeGrandPrize[]>
  // month index: number of months from Jan.1970, DeGrand has only one time per every month
  mapping(uint256 => DeGrandPrize) private _deGrandPrizes;
  // <lotteryId, DeGrandWinner[]>
  mapping(uint256 => DeGrandWinner[]) private _deGrandWinners;
  // <ticketId, user address>
  mapping(uint256 => address) private _tickets;
  // <ticketId, claimed>: Claimed status for DeLotto second stage
  mapping(uint256 => bool) private _claimed;
  // <user address, <lotteryId, ticketId[]>>
  mapping(address => mapping(uint256 => uint256[]))
    private _userTicketIdsPerLotteryId;

  // Maximum number of tickets to be awarded on DeLotto second stage
  uint256 public constant MAX_DELOTTO_SECOND_TICKETS = 100;

  modifier onlyOperator() {
    require(msg.sender == operatorAddress, "Operator is required");
    _;
  }

  event LotteryOpen(
    uint256 indexed lotteryId,
    uint256 startTime,
    uint256 endTime,
    uint256 priceTicketInDehub,
    uint256 firstTicketId,
    uint256 unwonPreviousPot
  );
  event LotteryClose(
    uint256 indexed lotteryId,
    uint256 firstTicketIdNextLottery
  );
  event PickAwardWinners(
    uint256 indexed lotteryId,
    uint256 maxPickedCount,
    uint256 finalNumber
  );
  event SetDeGrandPrize(
    uint256 monthIndex,
    string title,
    string subtitle,
    uint256 maxNumberDeGrandWinners
  );
  event RemoveDeGrandPrize(uint256 monthIndex);
  event PickDeGrandWinners(
    uint256 indexed lotteryId,
    uint256 drawTime,
    uint256 maxWinnerCount,
    uint256 finalNumber
  );
  event TicketsPurchase(
    address indexed buyer,
    uint256 indexed lotteryId,
    uint256 numberTickets
  );
  event TicketsClaim(
    address indexed claimer,
    uint256 amount,
    uint256 indexed lotteryId,
    uint256 numberTickets
  );
  event IncreasePot(uint256 indexed lotteryId, uint256 amount);

  function __SpecialLottery_init(
    IERC20Upgradeable _dehubToken,
    IDeHubRand _randomGenerator
  ) public initializer {
    DeHubLotterysUpgradeable.initialize();

    currentLotteryId = 0;
    currentTicketId = 1;
    unwonPreviousPot = 0;

    dehubToken = _dehubToken;
    randomGenerator = _randomGenerator;

    transfererAddress = msg.sender;

    maxNumberTicketsPerBuyOrClaim = 100;

    maxPriceTicketInDehub = 50000 * (10**5);
    minPriceTicketInDehub = 1000 * (10**5);

    breakDownDeLottoPot = 7000; // 70%
    breakDownTeamWallet = 2000; // 20%
    breakDownBurn = 1000; // 10%
  }

  /**
   * @notice Buys tickets for the current lottery staking $Dehub
   * @param _lotteryId lottery id
   * @param _ticketCount purchased ticket count
   * @dev Callable by users
   */
  function buyTickets(uint256 _lotteryId, uint256 _ticketCount)
    external
    notContract
    nonReentrant
    whenNotPaused
  {
    require(_ticketCount <= maxNumberTicketsPerBuyOrClaim, "Too many tickets");

    require(
      _lotteries[_lotteryId].deLottoStatus == Status.Open,
      "Lottery is not open"
    );
    require(
      block.timestamp < _lotteries[_lotteryId].endTime,
      "Lottery is over"
    );

    // Calculate number of $Dehub to breakdown
    uint256 amountDehubToTransfer = _calculateTotalPriceForBulkTickets(
      _lotteries[_lotteryId].ticketRate,
      _ticketCount
    );

    uint256 deLottoAmount = amountDehubToTransfer.mul(breakDownDeLottoPot).div(
      10000
    );
    uint256 teamAmount = amountDehubToTransfer.mul(breakDownTeamWallet).div(
      10000
    );
    dehubToken.safeTransferFrom(
      address(msg.sender),
      address(deLottoAddress),
      deLottoAmount
    );
    dehubToken.safeTransferFrom(address(msg.sender), teamWallet, teamAmount);
    dehubToken.safeTransferFrom(
      address(msg.sender),
      DEAD_ADDRESS,
      amountDehubToTransfer.sub(deLottoAmount).sub(teamAmount)
    );

    _lotteries[_lotteryId].amountCollectedToken += deLottoAmount;

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
  function claimTickets(uint256 _lotteryId, uint256[] calldata _ticketIds)
    external
    notContract
    nonReentrant
    whenNotPaused
  {
    require(_ticketIds.length != 0, "Length must be >0");
    require(
      _ticketIds.length <= maxNumberTicketsPerBuyOrClaim,
      "Too many tickets"
    );
    require(
      _lotteries[_lotteryId].deLottoStatus == Status.Claimable,
      "Lottery not claimable"
    );
    require(_lotteryId == currentLotteryId, "Not a current round");

    // Initializes the rewardInDehubToTransfer
    uint256 rewardInDehubToTransfer;

    for (uint256 i = 0; i < _ticketIds.length; i++) {
      uint256 thisTicketId = _ticketIds[i];

      require(
        _lotteries[_lotteryId].firstTicketIdNextLottery > thisTicketId,
        "TicketId too high"
      );
      require(
        _lotteries[_lotteryId].firstTicketId <= thisTicketId,
        "TicketId too low"
      );
      require(msg.sender == _tickets[thisTicketId], "Not the owner");
      if (_claimed[thisTicketId]) {
        continue;
      }

      // Calculate reward of DeLotto second stage
      uint256 rewardForTicketId = _calculateRewardsForTicketId(
        _lotteryId,
        thisTicketId
      );

      _claimed[thisTicketId] = true;

      // Increment the reward to transfer
      rewardInDehubToTransfer += rewardForTicketId;
    }

    if (rewardInDehubToTransfer < 1) {
      // nothing to claim
      return;
    }

    // Transfer money to msg.sender
    deLottoAddress.transferTo(msg.sender, rewardInDehubToTransfer);

    emit TicketsClaim(
      msg.sender,
      rewardInDehubToTransfer,
      _lotteryId,
      _ticketIds.length
    );
  }

  /**
   * @notice Close the lottery
   * @param _lotteryId lottery id
   * @dev Callabel by operator
   */
  function closeLottery(uint256 _lotteryId)
    external
    onlyOperator
    nonReentrant
    whenNotPaused
  {
    require(
      _lotteries[_lotteryId].deLottoStatus == Status.Open,
      "Lottery not open"
    );
    require(
      block.timestamp >= _lotteries[_lotteryId].endTime,
      "Lottery not over"
    );
    _lotteries[_lotteryId].firstTicketIdNextLottery = currentTicketId;

    // Request a random number from the generator based on a seed
    randomGenerator.getRandomNumber();

    _lotteries[_lotteryId].deLottoStatus = Status.Close;
    _lotteries[_lotteryId].deGrandStatus = Status.Close;

    emit LotteryClose(_lotteryId, currentTicketId);
  }

  /**
   * @notice View DeGrand prize
   * @param _timestamp draw timestamp to get month index
   * @dev Callable by users
   */
  function viewDeGrandPrize(uint256 _timestamp)
    external
    view
    returns (DeGrandPrize memory)
  {
    uint256 deGrandMonth = _timestamp / 2629800; // 2629800 is a month in seconds
    return _deGrandPrizes[deGrandMonth];
  }

  /**
   * @notice View DeGrand prize by lottery id
   * @param _lotteryId lottery id
   * @dev Callable by users
   */
  function viewDeGrandPrizeByLotteryId(uint256 _lotteryId)
    external
    view
    returns (DeGrandPrize memory)
  {
    uint256 deGrandMonth = _lotteries[_lotteryId].startTime / 2629800; // 2629800 is a month in seconds
    return _deGrandPrizes[deGrandMonth];
  }

  /**
   * @notice Set DeGrand Prize
   * @param _timestamp draw timestamp to get month index
   * @param _title Prize title
   * @param _subtitle Prize subtitle
   * @param _description Prize description
   * @param _ctaUrl URL link to more info
   * @param _imageUrl URL link to a graphic image
   * @param _maxNumberDeGrandWinners Maximum number of winners to get prize
   * @dev Callable by operator, Dehub team can set prize while DeLotto stage1 goes on
   *      or before DeGrand stage closes.
   */
  function setDeGrandPrize(
    uint256 _timestamp,
    string memory _title,
    string memory _subtitle,
    string memory _description,
    string memory _ctaUrl,
    string memory _imageUrl,
    uint256 _maxNumberDeGrandWinners
  ) external onlyOwner {
    require(_timestamp > block.timestamp, "Wrong draw time");
    require(_maxNumberDeGrandWinners < 128, "Maximum limit of winners is 128");
    require(bytes(_title).length > 0, "Empty prize title");

    uint256 deGrandMonth = _timestamp / 2629800; // 2629800 is a month in seconds
    _deGrandPrizes[deGrandMonth] = DeGrandPrize({
      drawTime: _timestamp,
      title: _title,
      subtitle: _subtitle,
      description: _description,
      ctaUrl: _ctaUrl,
      imageUrl: _imageUrl,
      maxWinnerCount: _maxNumberDeGrandWinners,
      picked: false
    });

    emit SetDeGrandPrize(
      deGrandMonth,
      _title,
      _subtitle,
      _maxNumberDeGrandWinners
    );
  }

  /**
   * @notice Remove DeGrand prize, do not allow to remove after draw.
   * @param _timestamp draw timestamp to get month index
   * @dev Callable by operator
   */
  function removeDeGrandPrize(uint256 _timestamp) external onlyOwner {
    uint256 deGrandMonth = _timestamp / 2629800; // 2629800 is a month in seconds
    require(
      _deGrandPrizes[deGrandMonth].drawTime > 0,
      "DeGrand Prize was not set"
    );
    require(
      !_deGrandPrizes[deGrandMonth].picked,
      "DeGrand Prize already picked"
    );

    delete _deGrandPrizes[deGrandMonth];
  }

  /**
   * @notice Picks the number of winners by the DeHub team. Only used for the DeGrand lottery
   * @param _lotteryId lottery id
   * @dev Callable by operator
   */
  function pickDeGrandWinners(uint256 _lotteryId)
    external
    onlyOwner
    nonReentrant
    whenNotPaused
  {
    require(
      _lotteries[_lotteryId].deGrandStatus == Status.Close ||
        _lotteries[_lotteryId].deGrandStatus == Status.Claimable,
      "Lottery not closed and claimable"
    );
    require(
      _lotteryId == randomGenerator.viewLatestId(address(this)),
      "Numbers not drawn"
    );

    uint256 deGrandMonth = _lotteries[_lotteryId].startTime / 2629800; // 2629800 is a month in seconds
    require(
      _deGrandPrizes[deGrandMonth].drawTime > 0,
      "DeGrand Prize was not set"
    );
    require(
      !_deGrandPrizes[deGrandMonth].picked,
      "DeGrand Prize already picked"
    );
    uint256 maxWinnerCount = _deGrandPrizes[deGrandMonth].maxWinnerCount;
    require(
      maxWinnerCount > 0 && maxWinnerCount < 128,
      "Number of winners is between 1 to 128"
    );
    uint256 ticketCount = _lotteries[_lotteryId].firstTicketIdNextLottery -
      _lotteries[_lotteryId].firstTicketId;
    require(maxWinnerCount <= ticketCount, "Picking more than tickets total!");

    // Calculate the finalNumber based on the randomResult generated by ChainLink's fallback
    uint256 finalNumber = randomGenerator.viewRandomResult256(address(this));

    for (uint256 i = 0; i < maxWinnerCount; i++) {
      uint256 pickNumber = Utils.pickNumberInRandom(
        finalNumber,
        i,
        ticketCount
      );
      uint256 ticketId = pickNumber + _lotteries[_lotteryId].firstTicketId;
      if (!_deGrandWinnerTicketIds[_lotteryId][ticketId]) {
        _deGrandWinnerTicketIds[_lotteryId][ticketId] = true;
        _deGrandWinners[_lotteryId].push(
          DeGrandWinner({user: _tickets[ticketId], ticketId: ticketId})
        );
      }
    }

    // Update internal statuses for lottery
    _lotteries[_lotteryId].deGrandMaximumWinners = maxWinnerCount;
    _lotteries[_lotteryId].deGrandFinalNumber = finalNumber;
    _lotteries[_lotteryId].deGrandStatus = Status.Claimable;

    // Update picked status for DeGrandPrize
    _deGrandPrizes[deGrandMonth].picked = true;

    emit PickDeGrandWinners(
      _lotteryId,
      _deGrandPrizes[deGrandMonth].drawTime,
      maxWinnerCount,
      finalNumber
    );
  }

  /**
   * @notice Picks the number of winners. Only used for the DeLotto second stage
   * @param _lotteryId lottery id
   * @dev Callable by operator
   */
  function pickAwardWinners(uint256 _lotteryId)
    external
    onlyOperator
    nonReentrant
    whenNotPaused
  {
    require(
      _lotteries[_lotteryId].deLottoStatus == Status.Close ||
        _lotteries[_lotteryId].deLottoStatus == Status.Claimable,
      "Lottery not closed"
    );
    require(
      _lotteryId == randomGenerator.viewLatestId(address(this)),
      "Numbers not drawn"
    );

    _lotteries[_lotteryId].deLottoStatus = Status.Claimable;

    uint256 ticketCount = _lotteries[_lotteryId].firstTicketIdNextLottery -
      _lotteries[_lotteryId].firstTicketId;
    if (ticketCount <= MAX_DELOTTO_SECOND_TICKETS) {
      emit PickAwardWinners(_lotteryId, ticketCount, 0);
      return;
    }

    // Calculate the finalNumber based on the randomResult generated by ChainLink's fallback
    uint256 finalNumber = randomGenerator.viewRandomResult256(address(this));

    // If bought over 100 tickets, pick randomly 100 tickets
    for (uint256 i = 0; i < MAX_DELOTTO_SECOND_TICKETS; i++) {
      uint256 pickNumber = Utils.pickNumberInRandom(
        finalNumber,
        i,
        ticketCount
      );
      _deLottoWinnerTicketIds[_lotteryId][
        pickNumber + _lotteries[_lotteryId].firstTicketId
      ] = true;
    }

    // Update internal statuses for lottery
    _lotteries[_lotteryId].deLottoFinalNumber = finalNumber;

    emit PickAwardWinners(_lotteryId, MAX_DELOTTO_SECOND_TICKETS, finalNumber);
  }

  /**
   * @notice Start the lottery
   * @param _endTime end time of the lottery
   * @param _ticketRate price of a ticket in $Dehub
   * @dev Callable by operator
   */
  function startLottery(uint256 _endTime, uint256 _ticketRate)
    external
    onlyOperator
    whenNotPaused
  {
    require(
      (currentLotteryId == 0) ||
        (_lotteries[currentLotteryId].deLottoStatus == Status.Claimable),
      "Not time to start lottery"
    );
    require(
      (_ticketRate >= minPriceTicketInDehub) &&
        (_ticketRate <= maxPriceTicketInDehub),
      "Outside of limits"
    );

    currentLotteryId++;

    uint256 unwonPreviousPot = deLottoAddress.viewLastUnwonPot();

    _lotteries[currentLotteryId] = Lottery({
      deLottoStatus: Status.Open,
      deGrandStatus: Status.Open,
      startTime: block.timestamp,
      endTime: _endTime,
      ticketRate: _ticketRate,
      unwonPreviousPot: unwonPreviousPot,
      amountCollectedToken: 0,
      firstTicketId: currentTicketId,
      firstTicketIdNextLottery: currentTicketId,
      deGrandFinalNumber: 0,
      deGrandMaximumWinners: 0,
      deLottoFinalNumber: 0
    });

    emit LotteryOpen(
      currentLotteryId,
      block.timestamp,
      _endTime,
      _ticketRate,
      currentTicketId,
      unwonPreviousPot
    );
  }

  /**
   * @notice Increase pot by DeHub team
   * @param _lotteryId lottery id
   * @param _amount amount to increase pot
   * @dev Callable by owner
   */
  function increasePot(uint256 _lotteryId, uint256 _amount)
    external
    nonReentrant
    whenNotPaused
    onlyOwner
  {
    require(
      _lotteries[_lotteryId].deLottoStatus == Status.Open,
      "Lottery is not open"
    );

    dehubToken.safeTransferFrom(address(msg.sender), address(this), _amount);

    _lotteries[_lotteryId].amountCollectedToken += _amount;

    emit IncreasePot(_lotteryId, _amount);
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
    require(
      _minPriceTicketInDehub <= _maxPriceTicketInDehub,
      "minPrice must be < maxPrice"
    );

    minPriceTicketInDehub = _minPriceTicketInDehub;
    maxPriceTicketInDehub = _maxPriceTicketInDehub;
  }

  /**
   * @notice Set the maximum number of tickets to buy or claim
   * @param _maxNumberTicketsPerBuyOrClaim maximum number of tickets to buy or claim
   * @dev Callable by owner
   */
  function setMaxNumberTicketsPerBuyOrClaim(
    uint256 _maxNumberTicketsPerBuyOrClaim
  ) external onlyOwner {
    require(_maxNumberTicketsPerBuyOrClaim > 0, "Must be > 0");
    maxNumberTicketsPerBuyOrClaim = _maxNumberTicketsPerBuyOrClaim;
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
   * @notice Set DeLotto address
   * @param _address DeLotto address
   * @dev Callable by owner
   */
  function setDeLottoAddress(DeHubLotterysAbstract _address)
    external
    onlyOwner
  {
    deLottoAddress = _address;
  }

  /**
   * @notice View lottery information
   * @param _lotteryId lottery id
   * @dev Callable by users
   */
  function viewLottery(uint256 _lotteryId)
    external
    view
    returns (Lottery memory)
  {
    return _lotteries[_lotteryId];
  }

  /**
   * @notice View lottery drawed status and final number
   * @param _lotteryId lottery id
   * @dev Callable by users
   */
  function viewLotteryDrawable(uint256 _lotteryId)
    external
    view
    returns (Status, Status)
  {
    return (
      _lotteries[_lotteryId].deLottoStatus,
      _lotteries[_lotteryId].deGrandStatus
    );
  }

  /**
   * @notice View DeLotto second stage rewards for ticket ids
   * @param _lotteryId lottery id
   * @param _ticketIds array of ticket ids
   */
  function viewDeLottoRewardsForTicketIds(
    uint256 _lotteryId,
    uint256[] calldata _ticketIds
  ) external view returns (uint256) {
    // Check if lottery is in claimable status
    if (_lotteries[_lotteryId].deLottoStatus != Status.Claimable) {
      return 0;
    }

    uint256 rewards;
    for (uint256 i = 0; i < _ticketIds.length; i++) {
      if (_claimed[_ticketIds[i]]) {
        continue;
      }

      // Calculate reward of DeLotto second stage
      uint256 rewardForTicketId = _calculateRewardsForTicketId(
        _lotteryId,
        _ticketIds[i]
      );

      // Increment the reward to transfer
      rewards += rewardForTicketId;
    }
    return rewards;
  }

  /**
   * @notice View all winning status of DeLotto second stage for ticket ids
   * @param _lotteryId lottery id
   * @param _ticketIds array of ticket id to check
   */
  function viewDeLottoWinningForTicketIds(
    uint256 _lotteryId,
    uint256[] calldata _ticketIds
  )
    external
    view
    returns (
      bool[] memory // array of winning status
    )
  {
    uint256 ticketCount = _ticketIds.length;

    bool[] memory winnings = new bool[](ticketCount);

    uint256 lotteryTicketCount = _lotteries[_lotteryId]
      .firstTicketIdNextLottery - _lotteries[_lotteryId].firstTicketId;

    if (lotteryTicketCount > MAX_DELOTTO_SECOND_TICKETS) {
      for (uint256 i = 0; i < ticketCount; i++) {
        winnings[i] = _deLottoWinnerTicketIds[_lotteryId][_ticketIds[i]];
      }
    } else {
      // not exceeded 100, all the tickets are winning tickets.
      for (uint256 i = 0; i < ticketCount; i++) {
        winnings[i] = true;
      }
    }

    return winnings;
  }

  /**
   * @notice View all winning status of DeGrand stage for ticket ids
   * @param _lotteryId lottery id
   * @param _ticketIds array of ticket id to check
   */
  function viewDeGrandWinningForTicketIds(
    uint256 _lotteryId,
    uint256[] calldata _ticketIds
  )
    external
    view
    returns (
      bool[] memory // array of winning status
    )
  {
    uint256 ticketCount = _ticketIds.length;

    bool[] memory winnings = new bool[](ticketCount);

    for (uint256 i = 0; i < ticketCount; i++) {
      winnings[i] = _deGrandWinnerTicketIds[_lotteryId][_ticketIds[i]];
    }

    return winnings;
  }

  /**
   * @notice View all picked status of DeGrand stage for ticket ids
   * @param _lotteryId lottery id
   */
  function viewDeGrandStatusForTicketIds(uint256 _lotteryId)
    external
    view
    returns (
      address[] memory, // array of ticket owner
      uint256[] memory // array of ticket id
    )
  {
    uint256 ticketCount = _deGrandWinners[_lotteryId].length;

    address[] memory ticketOwners = new address[](ticketCount);
    uint256[] memory ticketIds = new uint256[](ticketCount);

    for (uint256 i = 0; i < ticketCount; i++) {
      ticketOwners[i] = _deGrandWinners[_lotteryId][i].user;
      ticketIds[i] = _deGrandWinners[_lotteryId][i].ticketId;
    }

    return (ticketOwners, ticketIds);
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
  )
    external
    view
    returns (
      uint256[] memory, // array of ticket ids
      bool[] memory, // array of claimed status
      uint256 // next cursor
    )
  {
    uint256 length = _size;
    uint256 numberTicketsBoughtAtLotteryId = _userTicketIdsPerLotteryId[_user][
      _lotteryId
    ].length;

    if (length > (numberTicketsBoughtAtLotteryId - _cursor)) {
      length = numberTicketsBoughtAtLotteryId - _cursor;
    }

    uint256[] memory lotteryTicketIds = new uint256[](length);
    bool[] memory ticketStatuses = new bool[](length);

    for (uint256 i = 0; i < length; i++) {
      lotteryTicketIds[i] = _userTicketIdsPerLotteryId[_user][_lotteryId][
        i + _cursor
      ];

      ticketStatuses[i] = _claimed[lotteryTicketIds[i]];
    }

    return (lotteryTicketIds, ticketStatuses, _cursor + length);
  }

  /**
   * @notice Calculate DeLotto second stage rewards for a given ticket
   * @param _lotteryId: lottery id
   * @param _ticketId: ticket id
   * @return lottery reward
   */
  function _calculateRewardsForTicketId(uint256 _lotteryId, uint256 _ticketId)
    internal
    view
    returns (uint256)
  {
    uint256 ticketCount = _lotteries[_lotteryId].firstTicketIdNextLottery -
      _lotteries[_lotteryId].firstTicketId;
    uint256 deLottoPot = _lotteries[_lotteryId].unwonPreviousPot +
      _lotteries[_lotteryId].amountCollectedToken;

    // DeLotto second stage
    if (ticketCount > MAX_DELOTTO_SECOND_TICKETS) {
      // If bought over 100 tickets, pick randomly 100 tickets
      if (_deLottoWinnerTicketIds[_lotteryId][_ticketId]) {
        // every ticket has 1% of unwon pot
        return deLottoPot.div(100);
      }
    } else {
      // every ticket has 1% of unwon pot
      return deLottoPot.div(100);
    }
    return 0;
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
   * @dev Must call this jsut after the upgrade deployement, to update state
   * variables and execute other upgrade logic.
   * Ref: https://github.com/OpenZeppelin/openzeppelin-upgrades/issues/62
   */
  function upgradeToV2() public {
    require(version < 2, "SpecialLottery: Already upgraded to version 2");
    version = 2;
    console.log("v", version);
  }
}
