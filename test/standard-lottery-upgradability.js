const { BigNumber } = require("@ethersproject/bignumber");
const { expect } = require("chai");
const { ethers } = require("hardhat");
const {
  now,
  increaseTime,
  setBlockTime,
  generateTicketNumbers,
} = require("./utils/common");

const upgradeInstance = async (admin, addressV1) => {
  const StandardLotteryV2 = await ethers.getContractFactory(
    "StandardLotteryV2",
    admin
  );
  
  const standardLotteryV2 = await upgrades.upgradeProxy(
    addressV1,
    StandardLotteryV2
  );
  standardLotteryV2.upgradeToV2();
  return standardLotteryV2;
};

describe("StandardLottery-upgradability", () => {
  const DEHUB_PRICE = 50000 * 100000;
  const SIX_HOUR = 3600 * 6;

  let admin, operator, degrand, alpha, beta, gamma;
  let addrs;

  let lotteryStartTime, lotteryEndTime;

  beforeEach(async () => {
    [admin, operator, degrand, alpha, beta, gamma, ...addrs] = await ethers.getSigners();

    const DehubToken = await ethers.getContractFactory("MockERC20", admin);
    const DehubRandom = await ethers.getContractFactory("MockDehubFixedRand", admin);
    const StandardLottery = await ethers.getContractFactory(
      "StandardLottery",
      admin
    );
    const SpecialLottery = await ethers.getContractFactory(
      "SpecialLottery",
      admin
    );

    this.dehubToken = await DehubToken.deploy("Dehub", "$Dehub", BigNumber.from("1000000000000"));
    await this.dehubToken.deployed();
    this.dehubRandom = await DehubRandom.deploy();
    await this.dehubRandom.deployed();
    this.standardLottery = await upgrades.deployProxy(
      StandardLottery,
      [this.dehubToken.address, this.dehubRandom.address],
      {
        kind: "uups",
        initializer: "__StandardLottery_init",
      }
    );
    await this.standardLottery.deployed();
    this.specialLottery = await upgrades.deployProxy(
      SpecialLottery,
      [this.dehubToken.address, this.dehubRandom.address],
      {
        kind: "uups",
        initializer: "__SpecialLottery_init",
      }
    );
    await this.specialLottery.deployed();

    await this.dehubToken.transfer(alpha.address, BigNumber.from("100000000000"));
    await this.dehubToken.transfer(beta.address, BigNumber.from("100000000000"));
    await this.dehubToken.transfer(gamma.address, BigNumber.from("100000000000"));

    /// Initialize Lottery
    // Set operator address
    await this.standardLottery.setOperatorAddress(operator.address);
    // Set DeGrand address
    await this.standardLottery.setDeGrandAddress(degrand.address);
    // Set team address
    await this.standardLottery.setTeamWallet(operator.address);
    // Set breakdown percent
    await this.standardLottery.setBreakdownPercent(
      5000, // DeLotto pot
      3000, // DeGrand pot
      1000, // Team Wallet
      1000 // Burn
    );

    /// Start Lottery
    lotteryStartTime = await now();
    lotteryEndTime = lotteryStartTime + SIX_HOUR;
    await this.standardLottery.connect(operator).startLottery(
      lotteryEndTime, // lottery endtime
      DEHUB_PRICE, // price in $Dehub
      [0, 1000, 2500, 10000] // [zero, Bronze, Silver, Gold] breakdown
    );
  });

  it("user tickets must be preserved", async () => {
    const lotteryId = await this.standardLottery.viewCurrentTaskId();

    const initBalance = await this.dehubToken.balanceOf(
      this.standardLottery.address
    );

    /// Buy ticket
    const alphaTickets = generateTicketNumbers(10);
    await this.dehubToken
      .connect(alpha)
      .approve(this.standardLottery.address, DEHUB_PRICE * alphaTickets.length);
    await this.standardLottery.connect(alpha).buyTickets(
      lotteryId,
      alphaTickets.length, // purchased ticket count
      alphaTickets
    );

    const standardLotteryV2 = await upgradeInstance(admin.address, this.standardLottery.address);

    // Get ticket ids
    const userInfo = await standardLotteryV2
      .connect(alpha)
      .viewUserInfoForLotteryId(alpha.address, lotteryId, 0, 100);

    const ticketNumbers = userInfo[1];
    alphaTickets.forEach((alphaTicket, index) => {
      expect(alphaTicket).to.equal(ticketNumbers[index]);
    });

    expect(
      (await this.dehubToken.balanceOf(standardLotteryV2.address)) -
        initBalance
    ).to.equal(DEHUB_PRICE * alphaTickets.length / 2); // 50%
  });

  it("prize pot must be preserved", async () => {
    const lotteryId = await this.standardLottery.viewCurrentTaskId();

    const initBalance = await this.dehubToken.balanceOf(
      this.standardLottery.address
    );

    /// Buy ticket
    const alphaTickets = generateTicketNumbers(10);
    await this.dehubToken
      .connect(alpha)
      .approve(this.standardLottery.address, DEHUB_PRICE * alphaTickets.length);
    await this.standardLottery.connect(alpha).buyTickets(
      lotteryId,
      alphaTickets.length, // purchased ticket count
      alphaTickets
    );

    const totalTransferAmount = DEHUB_PRICE * alphaTickets.length;

    /// Upgrade contract
    const standardLotteryV2 = await upgradeInstance(admin.address, this.standardLottery.address);

    /// Check balance
    expect(
      (await this.dehubToken.balanceOf(standardLotteryV2.address)) -
        initBalance
    ).to.equal(totalTransferAmount / 2); // 50%

    const beforeIncreasePot = await this.dehubToken.balanceOf(
      standardLotteryV2.address
    );
    
    /// Increase pot by previous contract instance
    await this.dehubToken.approve(standardLotteryV2.address, 3000);
    await standardLotteryV2.increasePot(lotteryId, 3000);

    expect(
      (await this.dehubToken.balanceOf(standardLotteryV2.address)) -
        beforeIncreasePot
    ).to.equal(3000);
  });

  it("must be claimable tickets", async () => {
    const lotteryId = await this.standardLottery.viewCurrentTaskId();

    /// Buy ticket
    const alphaTickets = [
      102070406, 115030803, 101140803, 106150208
    ];
    await this.dehubToken
      .connect(alpha)
      .approve(this.standardLottery.address, DEHUB_PRICE * alphaTickets.length);
    await this.standardLottery.connect(alpha).buyTickets(
      lotteryId,
      alphaTickets.length, // purchased ticket count
      alphaTickets
    );

    const deLottoAmount = DEHUB_PRICE * alphaTickets.length / 2; // 50%	Towards	DeLotto	pot

    /// Close Lottery
    await setBlockTime(lotteryEndTime);
    await this.standardLottery.connect(operator).closeLottery(lotteryId);

    /// Set random result manually to match with tickets.
    // Let us make a silver prize for third ticket.
    const randomResult = 102130702; // considering _wrappingFinalNumber()
    await this.dehubRandom.setRandomResult(randomResult);
    expect(await this.dehubRandom
      .viewRandomResult256(this.standardLottery.address)).to.equal(randomResult);

    /// Draw lottery
    await this.standardLottery.connect(operator).drawFinalNumber(lotteryId);

    const userInfo = await this.standardLottery
      .connect(alpha)
      .viewUserInfoForLotteryId(alpha.address, lotteryId, 0, 100);

    /// Check rewards
    // Check rewards of triple matched number
    const ticketId3 = userInfo[0][2]; // third ticket id
    const bracket3 = 2;
    const rewards3 = await this.standardLottery
      .viewRewardsForTicketId(lotteryId, ticketId3, bracket3);
    expect(rewards3).to.equal(deLottoAmount * 2500 / 10000); // silver percent

    const initBalance = await this.dehubToken.balanceOf(alpha.address);

    /// Upgrade contract
    const standardLotteryV2 = await upgradeInstance(admin.address, this.standardLottery.address);

    /// Claim tickets
    const bracketIds = [0, 0, 2, 0];
    await standardLotteryV2
      .connect(alpha)
      .claimTickets(lotteryId, userInfo[0], bracketIds);

    expect(
      (await this.dehubToken.balanceOf(alpha.address)) - initBalance
    ).to.equal(deLottoAmount * 2500 / 10000);

    // Check if there are not claimable tickets
    const userInfoAfterClaim = await standardLotteryV2
      .connect(alpha)
      .viewUserInfoForLotteryId(alpha.address, lotteryId, 0, 100);
    let unclaimed = 0;
    userInfoAfterClaim[2].forEach((claimed) => (unclaimed |= !claimed));
    expect(unclaimed).to.equal(0);
  });

  it("claimable while upgrading", async () => {
    const lotteryId = await this.standardLottery.viewCurrentTaskId();

    /// Buy ticket
    const alphaTickets = [
      102070406, 115030803, 101140803, 106140803
    ];
    await this.dehubToken
      .connect(alpha)
      .approve(this.standardLottery.address, DEHUB_PRICE * alphaTickets.length);
    await this.standardLottery.connect(alpha).buyTickets(
      lotteryId,
      alphaTickets.length, // purchased ticket count
      alphaTickets
    );

    const deLottoAmount = DEHUB_PRICE * alphaTickets.length / 2; // 50%	Towards	DeLotto	pot

    /// Close Lottery
    await setBlockTime(lotteryEndTime);
    await this.standardLottery.connect(operator).closeLottery(lotteryId);

    /// Set random result manually to match with tickets.
    // Let us make a silver prize for third ticket.
    const randomResult = 105130702; // considering _wrappingFinalNumber()
    await this.dehubRandom.setRandomResult(randomResult);
    expect(await this.dehubRandom
      .viewRandomResult256(this.standardLottery.address)).to.equal(randomResult);

    /// Upgrade contract
    const standardLotteryV2 = await upgradeInstance(admin.address, this.standardLottery.address);

    /// Draw lottery
    await this.standardLottery.connect(operator).drawFinalNumber(lotteryId);

    // Fetch user ticket info from older version contract
    const userInfo = await this.standardLottery
      .connect(alpha)
      .viewUserInfoForLotteryId(alpha.address, lotteryId, 0, 100);

    /// Check rewards
    // Check rewards of double matched number
    const ticketId4 = userInfo[0][3]; // forth ticket id
    const bracket4 = 3;
    const rewards4 = await this.standardLottery
      .viewRewardsForTicketId(lotteryId, ticketId4, bracket4);
    expect(rewards4).to.equal(deLottoAmount); // gold percent

    const initBalance = await this.dehubToken.balanceOf(alpha.address);

    /// Claim tickets
    const bracketIds = [0, 0, 0, 3];
    await standardLotteryV2
      .connect(alpha)
      .claimTickets(lotteryId, userInfo[0], bracketIds);

    expect(
      (await this.dehubToken.balanceOf(alpha.address)) - initBalance
    ).to.equal(deLottoAmount);

    // Check if there are not claimable tickets
    const userInfoAfterClaim = await standardLotteryV2
      .connect(alpha)
      .viewUserInfoForLotteryId(alpha.address, lotteryId, 0, 100);
    let unclaimed = 0;
    userInfoAfterClaim[2].forEach((claimed) => (unclaimed |= !claimed));
    expect(unclaimed).to.equal(0);
  });

  it("success working after upgrading", async () => {
    const lotteryId = await this.standardLottery.viewCurrentTaskId();
    
    const deGrandInitBalance = await this.dehubToken.balanceOf(
      degrand.address
    );

    /// Upgrade contract
    const standardLotteryV2 = await upgradeInstance(admin.address, this.standardLottery.address);

    /// Buy ticket
    const alphaTickets = [
      102070406, 115030803, 101140803, 106140803
    ];
    await this.dehubToken
      .connect(alpha)
      .approve(standardLotteryV2.address, DEHUB_PRICE * alphaTickets.length);
    await standardLotteryV2.connect(alpha).buyTickets(
      lotteryId,
      alphaTickets.length, // purchased ticket count
      alphaTickets
    );

    const deGrandAmount = DEHUB_PRICE * alphaTickets.length * 3 / 10; // 30%	Towards	DeGrand	pot

    /// Check DeGrand wallet amount
    expect(
      (await this.dehubToken.balanceOf(degrand.address)) -
        deGrandInitBalance
    ).to.equal(deGrandAmount); // 30%
  });
});
