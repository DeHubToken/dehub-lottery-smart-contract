// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "hardhat/console.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "./abstracts/DeHubLotterysUpgradeable.sol";
import "./interfaces/IDeHubRand.sol";
import "./interfaces/IDeHubRandConsumer.sol";
import "./interfaces/ITransferable.sol";

contract StandardLottery is
  DeHubLotterysUpgradeable,
  IDeHubRandConsumer,
  ITransferable
{
  using SafeMathUpgradeable for uint256;
  using SafeERC20Upgradeable for IERC20Upgradeable;

  enum Status {
    Pending, // == 0
    Open, // == 1
    Close, // == 2
    Claimable, // == 3
    Burned // == 4
  }

  struct Lottery {
    Status status;
    uint256 startTime;
    uint256 endTime;
    uint256 ticketRate; // $Dehub price per ticket
    uint256[4] rewardBreakdown; // Gold, Silver, Bronze tier for DeLotto
    uint256[4] countWinnersPerBracket;
    uint256[4] tokenPerBracket;
    uint256 amountCollectedToken; // collected $Dehub token amount
    uint256 firstTicketId;
    uint256 firstTicketIdNextLottery;
    uint256 finalNumber; // 8 weight number, each two number is from 01~18
  }

  struct Ticket {
    uint256 number; // 8 weight number, each two number is from 01~18
    address owner;
  }

  struct BundleRule {
    uint256 purchasedTickets; // Number of purchasing tickets
    uint256 freeTickets; // Number of free tickets
  }

  address public operatorAddress; // Scheduler wallet address
  address public transfererAddress; // address who can tranfer
  address public deGrandAddress; // address to SpecialLottery
  address public teamWallet;
  address public constant deadAddress =
    0x000000000000000000000000000000000000dEaD;

  uint256 public currentLotteryId;
  uint256 public currentTicketId;

  uint256 public maxNumberTicketsPerBuyOrClaim;

  uint256 public maxPriceTicketInDehub;
  uint256 public minPriceTicketInDehub;

  uint256 public breakDownDeLottoPot;
  uint256 public breakDownDeGrandPot;
  uint256 public breakDownTeamWallet;
  uint256 public breakDownBurn;

  IERC20Upgradeable public dehubToken;

  IDeHubRand public randomGenerator;

  BundleRule[] public bundleRules;

  // <lotteryId, Lottery>
  mapping(uint256 => Lottery) _lotteries;
  // <ticketId, Ticket>
  mapping(uint256 => Ticket) _tickets;
  // Bracket calculator is used for verifying claims for ticket prizes
  mapping(uint256 => uint256) private _bracketCalculator;
  // <lotteryId, <number, count>>
  mapping(uint256 => mapping(uint256 => uint256)) _numberTicketsPerLotteryId;
  // <user address, <lotteryId, ticketId[]>>
  mapping(address => mapping(uint256 => uint256[])) _userTicketIdsPerLotteryId;

  uint256 public constant MIN_LENGTH_LOTTERY = 6 hours - 5 minutes; // 6 hours
  uint256 public constant MAX_LENGTH_LOTTERY = 6 days + 5 minutes; // 6 days

  uint256 public constant MAX_BUNDLE_RULES = 5;
  uint256 public constant MAX_TICKETS_PER_BUYCLAIM = 100;

  modifier onlyOperator() {
    require(msg.sender == operatorAddress, "Operator is required");
    _;
  }

  modifier onlyTransferer() {
    require(msg.sender == transfererAddress, "Transferer is required");
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
  event LotteryClose(
    uint256 indexed lotteryId,
    uint256 firstTicketIdNextLottery
  );
  event LotteryNumberDrawn(uint256 indexed lotteryId, uint256 finalNumber);
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

  function initialize(
    IERC20Upgradeable _dehubToken,
    IDeHubRand _randomGenerator
  ) public initializer {
    DeHubLotterysUpgradeable.initialize();

    dehubToken = _dehubToken;
    randomGenerator = _randomGenerator;

    transfererAddress = msg.sender;

    maxNumberTicketsPerBuyOrClaim = 100;

    maxPriceTicketInDehub = 50000;
    minPriceTicketInDehub = 1000;

    breakDownDeLottoPot = 5000; // 50%
    breakDownDeGrandPot = 3000; // 30%
    breakDownTeamWallet = 1000; // 10%
    breakDownBurn = 1000; // 10%

    // Initializes a mapping
    _bracketCalculator[0] = 11;
    _bracketCalculator[1] = 1111;
    _bracketCalculator[2] = 111111;
    _bracketCalculator[3] = 11111111;
  }

  /**
   * @notice Buy a bundle for the current lottery staking $Dehub
   * @param _lotteryId lottery id
   * @param _purchasedTicketCount purchased ticket count
   * @param _ticketNumbers ticket numbers, each number has 8 weight, every two numbers are 01~18
   * @dev Callable by users
   */
  function buyTickets(
    uint256 _lotteryId,
    uint256 _purchasedTicketCount,
    uint256[] calldata _ticketNumbers
  ) external notContract nonReentrant {
    require(_ticketNumbers.length != 0, "No ticket specified");
    require(
      _ticketNumbers.length <= maxNumberTicketsPerBuyOrClaim,
      "Too many tickets"
    );

    require(
      _lotteries[_lotteryId].status == Status.Open,
      "Lottery is not open"
    );
    require(
      block.timestamp < _lotteries[_lotteryId].endTime,
      "Lottery is over"
    );

    // According to bundle rule, return free tickets
    uint256 freeTickets = _viewBundleRule(_purchasedTicketCount);
    require(
      _purchasedTicketCount + freeTickets == _ticketNumbers.length,
      "Invalid ticket count"
    );

    // Calculate number of $Dehub to breakdown
    uint256 amountDehubToTransfer = _calculateTotalPriceForBulkTickets(
      _lotteries[_lotteryId].ticketRate,
      _purchasedTicketCount
    );

    uint256 deLottoAmount = amountDehubToTransfer.mul(breakDownDeLottoPot).div(
      10000
    );
    uint256 deGrandAmount = amountDehubToTransfer.mul(breakDownDeGrandPot).div(
      10000
    );
    uint256 teamAmount = amountDehubToTransfer.mul(breakDownTeamWallet).div(
      10000
    );
    dehubToken.safeTransferFrom(
      address(msg.sender),
      address(this),
      deLottoAmount
    );
    dehubToken.safeTransferFrom(
      address(msg.sender),
      deGrandAddress,
      deGrandAmount
    );
    dehubToken.safeTransferFrom(address(msg.sender), teamWallet, teamAmount);
    dehubToken.safeTransferFrom(
      address(msg.sender),
      deadAddress,
      amountDehubToTransfer.sub(deLottoAmount).sub(deGrandAmount).sub(
        teamAmount
      )
    );

    _lotteries[_lotteryId].amountCollectedToken += amountDehubToTransfer;

    for (uint256 i = 0; i < _ticketNumbers.length; i++) {
      uint256 ticketNumber = _ticketNumbers[i];

      require(ticketNumber >= 0 && ticketNumber <= 18181818, "Outside range");

      _numberTicketsPerLotteryId[_lotteryId][11 + (ticketNumber % 100)]++;
      _numberTicketsPerLotteryId[_lotteryId][1111 + (ticketNumber % 10000)]++;
      _numberTicketsPerLotteryId[_lotteryId][
        111111 + (ticketNumber % 1000000)
      ]++;
      _numberTicketsPerLotteryId[_lotteryId][
        11111111 + (ticketNumber % 100000000)
      ]++;

      _userTicketIdsPerLotteryId[msg.sender][_lotteryId].push(currentTicketId);

      _tickets[currentTicketId] = Ticket({
        number: ticketNumber,
        owner: msg.sender
      });

      // increase lottery ticket number
      currentTicketId++;
    }

    emit TicketsPurchase(msg.sender, _lotteryId, _ticketNumbers.length);
  }

  /**
   * @notice Claim a set of winning tickets for a lottery
   * @param _lotteryId lottery id
   * @param _ticketIds array of purchased ticket ids
   * @param _brackets array of brackets for the ticket ids
   * @dev Callable by users
   */
  function claimTickets(
    uint256 _lotteryId,
    uint256[] calldata _ticketIds,
    uint256[] calldata _brackets
  ) external notContract nonReentrant {
    require(_ticketIds.length == _brackets.length, "Not same length");
    require(_ticketIds.length != 0, "Length must be >0");
    require(
      _ticketIds.length <= maxNumberTicketsPerBuyOrClaim,
      "Too many tickets"
    );
    require(
      _lotteries[_lotteryId].status == Status.Claimable,
      "Lottery not claimable"
    );

    // Initializes the rewardInDehubToTransfer
    uint256 rewardInDehubToTransfer;

    for (uint256 i = 0; i < _ticketIds.length; i++) {
      require(_brackets[i] < 4, "Bracket out of range"); // Must be between 0 and 3

      uint256 thisTicketId = _ticketIds[i];

      require(
        _lotteries[_lotteryId].firstTicketIdNextLottery > thisTicketId,
        "TicketId too high"
      );
      require(
        _lotteries[_lotteryId].firstTicketId <= thisTicketId,
        "TicketId too low"
      );
      require(msg.sender == _tickets[thisTicketId].owner, "Not the owner");

      // Update the lottery ticket owner to 0x address
      _tickets[thisTicketId].owner = address(0);

      uint256 rewardForTicketId = _calculateRewardsForTicketId(
        _lotteryId,
        thisTicketId,
        _brackets[i]
      );

      // Increment the reward to transfer
      rewardInDehubToTransfer += rewardForTicketId;
    }

    // Transfer money to msg.sender
    dehubToken.safeTransfer(msg.sender, rewardInDehubToTransfer);

    emit TicketsClaim(
      msg.sender,
      rewardInDehubToTransfer,
      _lotteryId,
      _ticketIds.length
    );
  }

  /**
   * @notice Close lottery
   * @param _lotteryId lottery id
   * @dev Callable by operator
   */
  function closeLottery(uint256 _lotteryId) external onlyOperator nonReentrant {
    require(_lotteries[_lotteryId].status == Status.Open, "Lottery not open");
    require(
      block.timestamp >= _lotteries[_lotteryId].endTime,
      "Lottery not over"
    );
    _lotteries[_lotteryId].firstTicketIdNextLottery = currentTicketId;

    // Request a random number from the generator based on a seed
    randomGenerator.getRandomNumber();

    _lotteries[_lotteryId].status = Status.Close;

    emit LotteryClose(_lotteryId, currentTicketId);
  }

  /**
   * @notice Draws the final number, calculates the reward per all brackets, and makes the lottery claimable
   * @param _lotteryId lottery id
   * @dev Callable by operator
   */
  function drawFinalNumber(uint256 _lotteryId)
    external
    onlyOperator
    nonReentrant
  {
    require(_lotteries[_lotteryId].status == Status.Close, "Lottery not close");
    require(
      _lotteryId == randomGenerator.viewLatestId(address(this)),
      "Numbers not drawn"
    );

    // Calculate the finalNumber based on the randomResult generated by ChainLink"s fallback
    uint256 finalNumber = randomGenerator.viewRandomResult256(address(this));
    // DeLotto pot amount
    uint256 deLottoPot = dehubToken.balanceOf(address(this));
    uint256 previousCountWinners = 0;

    // Calculate prizes in $Dehub for each bracket by starting from the highest one
    for (uint256 i = 0; i < 4; i++) {
      uint256 j = 3 - i;
      uint256 transformedWinningNumber = _bracketCalculator[j] +
        (finalNumber % (uint256(100)**(j + 1)));

      // If number of users for this _bracket number is superior to 0
      _lotteries[_lotteryId].countWinnersPerBracket[
          i
        ] = _numberTicketsPerLotteryId[_lotteryId][transformedWinningNumber];
      if (
        _lotteries[_lotteryId].countWinnersPerBracket[i] > 0 &&
        previousCountWinners == 0
      ) {
        _lotteries[_lotteryId].tokenPerBracket[i] = deLottoPot
          .mul(_lotteries[_lotteryId].rewardBreakdown[i])
          .div(_lotteries[_lotteryId].countWinnersPerBracket[i]);
        previousCountWinners = _lotteries[_lotteryId].countWinnersPerBracket[i];
      } else {
        _lotteries[_lotteryId].tokenPerBracket[i] = 0;
      }
    }

    // Update internal statuses for lottery
    _lotteries[_lotteryId].finalNumber = finalNumber;
    _lotteries[_lotteryId].status = Status.Claimable;

    emit LotteryNumberDrawn(currentLotteryId, finalNumber);
  }

  /**
   * @notice Start the lottery
   * @param _endTime end time of the lottery
   * @param _ticketRate price of a ticket in $Dehub
   * @param _rewardBreakdown breakdown of rewards per bracket (must sum to 10,000)
   * @dev Callable by operator
   */
  function startLottery(
    uint256 _endTime,
    uint256 _ticketRate,
    uint256[4] calldata _rewardBreakdown
  ) external onlyOperator {
    require(
      (currentLotteryId == 0) ||
        (_lotteries[currentLotteryId].status == Status.Claimable),
      "Not time to start lottery"
    );
    // TODO
    // require(
    //   ((_endTime - block.timestamp) > MIN_LENGTH_LOTTERY) && ((_endTime - block.timestamp) < MAX_LENGTH_LOTTERY),
    //   "Lottery length outside of range"
    // );
    require(
      (_ticketRate >= minPriceTicketInDehub) &&
        (_ticketRate <= maxPriceTicketInDehub),
      "Outside of limits"
    );

    currentLotteryId++;

    _lotteries[currentLotteryId] = Lottery({
      status: Status.Open,
      startTime: block.timestamp,
      endTime: _endTime,
      ticketRate: _ticketRate,
      rewardBreakdown: _rewardBreakdown,
      countWinnersPerBracket: [uint256(0), uint256(0), uint256(0), uint256(0)],
      tokenPerBracket: [uint256(0), uint256(0), uint256(0), uint256(0)],
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
   * @notice Burn claimed pot
   * @param _lotteryId lottery id
   * @dev Callable by operator
   */
  function burnUnclaimed(uint256 _lotteryId) external onlyOperator {
    require(
      _lotteries[_lotteryId].status == Status.Claimable,
      "Not time to start lottery"
    );
    require(
      _lotteryId == randomGenerator.viewLatestId(address(this)),
      "Numbers not drawn"
    );

    uint256 remain = dehubToken.balanceOf(address(this));
    if (remain > 0) {
      dehubToken.safeTransfer(deadAddress, remain);
    }

    _lotteries[currentLotteryId].status = Status.Burned;
  }

  /**
   * @notice Transfers $Dehub to address
   * @param _addr destination address
   * @param _amount $Dehub token amount
   * @dev Callable by owner
   */
  function transferTo(address _addr, uint256 _amount)
    external
    override
    onlyTransferer
  {
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
    require(
      _maxNumberTicketsPerBuyOrClaim > 0 &&
        _maxNumberTicketsPerBuyOrClaim <= MAX_TICKETS_PER_BUYCLAIM,
      "Must be > 0"
    );
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
   * @notice Set transferer address
   * @param _address transferer address
   * @dev Callable by owner
   */
  function setTransfererAddress(address _address) external onlyOwner {
    transfererAddress = _address;
  }

  /**
   * @notice Set DeGrand address
   * @param _address DeGrand address
   * @dev Callable by owner
   */
  function setDeGrandAddress(address _address) external onlyOwner {
    deGrandAddress = _address;
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
   * @notice Sets discount rules for each bundle case
   * @param _purchasedTickets number of purchasing tickets
   * @param _freeTickets number of free tickets
   * @dev Callable by owner
   */
  function setBundleRule(uint256 _purchasedTickets, uint256 _freeTickets)
    external
    onlyOwner
  {
    for (uint256 i = 0; i < bundleRules.length; i++) {
      if (bundleRules[i].purchasedTickets == _purchasedTickets) {
        bundleRules[i].freeTickets = _freeTickets;
        return;
      }
    }

    require(bundleRules.length + 1 < MAX_BUNDLE_RULES, "Maximum bundle rules");
    bundleRules.push(
      BundleRule({
        purchasedTickets: _purchasedTickets,
        freeTickets: _freeTickets
      })
    );
  }

  function _viewBundleRule(uint256 _purchasedTickets)
    internal
    view
    returns (uint256)
  {
    if (bundleRules.length < 1) {
      return 0;
    }
    for (uint256 i = 0; i < bundleRules.length; i++) {
      if (bundleRules[i].purchasedTickets == _purchasedTickets) {
        return bundleRules[i].freeTickets;
      }
    }
    return 0;
  }

  /**
   * @notice View discount rules for each bundle case
   * @return array of purchased/free ticket rules
   * @dev Callable by users
   */
  function viewBundleRule()
    external
    view
    returns (uint256[] memory, uint256[] memory)
  {
    uint256[] memory purchasedCount = new uint256[](bundleRules.length);
    uint256[] memory freeCount = new uint256[](bundleRules.length);
    for (uint256 i = 1; i < bundleRules.length; i++) {
      purchasedCount[i] = bundleRules[i].purchasedTickets;
      freeCount[i] = bundleRules[i].freeTickets;
    }
    return (purchasedCount, freeCount);
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
   * @notice View rewards for ticket id
   * @param _lotteryId lottery id
   * @param _ticketId ticket id
   * @param _bracket bracket
   */
  function viewRewardsForTicketId(
    uint256 _lotteryId,
    uint256 _ticketId,
    uint256 _bracket
  ) external view returns (uint256) {
    // Check lottery is in claimable status
    if (_lotteries[_lotteryId].status != Status.Claimable) {
      return 0;
    }

    // Check ticketId is within range
    if (
      _lotteries[_lotteryId].firstTicketIdNextLottery < _ticketId &&
      _lotteries[_lotteryId].firstTicketId >= _ticketId
    ) {
      return 0;
    }

    return _calculateRewardsForTicketId(_lotteryId, _ticketId, _bracket);
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
      uint256[] memory, // array of ticket numbers
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
    uint256[] memory ticketNumbers = new uint256[](length);
    bool[] memory ticketStatuses = new bool[](length);

    for (uint256 i = 0; i < length; i++) {
      lotteryTicketIds[i] = _userTicketIdsPerLotteryId[_user][_lotteryId][
        i + _cursor
      ];
      ticketNumbers[i] = _tickets[lotteryTicketIds[i]].number;

      // True = ticket claimed
      if (_tickets[lotteryTicketIds[i]].owner == address(0)) {
        ticketStatuses[i] = true;
      } else {
        // ticket not claimed (includes the ones that cannot be claimed)
        ticketStatuses[i] = false;
      }
    }

    return (lotteryTicketIds, ticketNumbers, ticketStatuses, _cursor + length);
  }

  /**
   * @notice Calculate rewards for a given ticket
   * @param _lotteryId: lottery id
   * @param _ticketId: ticket id
   * @param _bracket: bracket for the ticketId to verify the claim and calculate rewards
   * @return lottery reward
   */
  function _calculateRewardsForTicketId(
    uint256 _lotteryId,
    uint256 _ticketId,
    uint256 _bracket
  ) internal view returns (uint256) {
    // Retrieve the winning number combination
    uint256 userNumber = _lotteries[_lotteryId].finalNumber;

    // Retrieve the user number combination from the ticketId
    uint256 winningTicketNumber = _tickets[_ticketId].number;

    // Apply transformation to verify the claim provided by the user is true
    uint256 transformedWinningNumber = _bracketCalculator[_bracket] +
      (winningTicketNumber % (uint256(100)**(_bracket + 1)));

    uint256 transformedUserNumber = _bracketCalculator[_bracket] +
      (userNumber % (uint256(100)**(_bracket + 1)));

    // Confirm that the two transformed numbers are the same, if not throw
    if (transformedWinningNumber == transformedUserNumber) {
      return _lotteries[_lotteryId].tokenPerBracket[_bracket];
    } else {
      return 0;
    }
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
