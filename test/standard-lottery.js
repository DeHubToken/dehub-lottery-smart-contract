const { expect } = require("chai");
const { ethers } = require("hardhat");
const { now, increaseTime, setBlockTime, generateTicketNumbers } = require("./utils/common");

describe("StandardLottery", () => {

  const DEHUB_PRICE = 50000;
  const SIX_HOUR = 3600 * 6;

  let admin, operator, alpha, beta, gamma;
  let addrs;

  let lotteryStartTime, lotteryEndTime;

  beforeEach(async () => {
    [admin, operator, alpha, beta, gamma, ...addrs] = await ethers.getSigners();

    const DehubToken = await ethers.getContractFactory("MockERC20", admin);
    const DehubRandom = await ethers.getContractFactory("MockDehubRand", admin);
    const StandardLottery = await ethers.getContractFactory("StandardLottery", admin);
    const SpecialLottery = await ethers.getContractFactory("SpecialLottery", admin);

    this.dehubToken = await DehubToken.deploy("Dehub", "$Dehub", 10000000);
    await this.dehubToken.deployed();
    this.dehubRandom = await DehubRandom.deploy();
    await this.dehubRandom.deployed();
    this.standardLottery = await StandardLottery.deploy(
      this.dehubToken.address,
      this.dehubRandom.address
    );
    await this.standardLottery.deployed();
    this.specialLottery = await SpecialLottery.deploy(
      this.dehubToken.address,
      this.dehubRandom.address
    );
    await this.specialLottery.deployed();

    await this.dehubToken.transfer(alpha.address, 1000000);
    await this.dehubToken.transfer(beta.address, 1000000);
    await this.dehubToken.transfer(gamma.address, 1000000);

    /// Initialize Lottery
    // Set operator address
    await this.standardLottery.setOperatorAddress(operator.address);
    // Set DeGrand address
    await this.standardLottery.setDeGrandAddress(this.specialLottery.address);
    // Set team address
    await this.standardLottery.setTeamWallet(operator.address);
    // Set breakdown percent
    await this.standardLottery.setBreakdownPercent(
      5000, // DeLotto pot
      3000, // DeGrand pot
      1000, // Team Wallet
      1000  // Burn
    );
    // Set bundle rules
    await this.standardLottery.setBundleRule(5, 1); // 5 purchased + 1 free
    await this.standardLottery.setBundleRule(10, 3); // 10 purchased + 3 free
    await this.standardLottery.setBundleRule(15, 5); // 15 purchased + 5 free

    /// Start Lottery
    lotteryStartTime = await now();
    lotteryEndTime = lotteryStartTime + SIX_HOUR;
    await this.standardLottery.connect(operator).startLottery(
      lotteryEndTime, // lottery endtime
      DEHUB_PRICE, // price in $Dehub
      [0, 1000, 2500, 10000] // [zero, Bronze, Silver, Gold] breakdown
    );
  })

  it("start/close lottery", async () => {
    // Close lottery before 6 hours, will occur error
    const lotteryId = await this.standardLottery.viewCurrentTaskId();

    await expect(this.standardLottery.connect(operator).closeLottery(lotteryId))
      .to.be.revertedWith('Lottery not over');

    // Pass 6 hours
    await increaseTime(SIX_HOUR);

    // Close lottery again
    await this.standardLottery.connect(operator).closeLottery(lotteryId);

    // Check lottery information
    const {
      status
    } = await this.standardLottery.viewLottery(lotteryId);
    expect(status).to.equal(2); // Close
  })

  it("buy tickets", async () => {
    const lotteryId = await this.standardLottery.viewCurrentTaskId();

    const deLottoInitBalance = await this.dehubToken.balanceOf(this.standardLottery.address);
    const deGrandInitBalance = await this.dehubToken.balanceOf(this.specialLottery.address);
    const operatorInitBalance = await this.dehubToken.balanceOf(operator.address);

    const alphaInitBalance = await this.dehubToken.balanceOf(alpha.address);
    const betaInitBalance = await this.dehubToken.balanceOf(beta.address);
    const gammaInitBalance = await this.dehubToken.balanceOf(gamma.address);

    /// Buy tickets with 3 accounts
    // Buy ticket without bundle discount
    const alphaTickets = generateTicketNumbers(2);
    await this.dehubToken.connect(alpha).approve(this.standardLottery.address, DEHUB_PRICE * 2);
    await this.standardLottery.connect(alpha)
      .buyTickets(
        lotteryId,
        2, // purchased ticket count
        alphaTickets
      );
    // Buy ticket appliable to bundle
    const betaTickets = generateTicketNumbers(6);
    await this.dehubToken.connect(beta).approve(this.standardLottery.address, DEHUB_PRICE * 6);
    await this.standardLottery.connect(beta)
      .buyTickets(
        lotteryId,
        6, // purchased ticket count
        betaTickets // 6 purchased, 0 free
      );
    // Buy ticket appliable to bundle
    const gammaTickets = generateTicketNumbers(13);
    await this.dehubToken.connect(gamma).approve(this.standardLottery.address, DEHUB_PRICE * 10);
    await this.standardLottery.connect(gamma)
      .buyTickets(
        lotteryId,
        10, // purchased ticket count
        gammaTickets
      );

    // Check buyer's token amount
    expect(alphaInitBalance - await this.dehubToken.balanceOf(alpha.address))
      .to.equal(DEHUB_PRICE * 2);
    expect(betaInitBalance - await this.dehubToken.balanceOf(beta.address))
      .to.equal(DEHUB_PRICE * 6);
    expect(gammaInitBalance - await this.dehubToken.balanceOf(gamma.address))
      .to.equal(DEHUB_PRICE * 10);

    const totalTransferAmount = DEHUB_PRICE * 18;

    /// Check if token was transfered to DeLotto, team, dead
    expect(await this.dehubToken.balanceOf(this.standardLottery.address) - deLottoInitBalance)
      .to.equal(totalTransferAmount / 2); // 50%
    expect(await this.dehubToken.balanceOf(this.specialLottery.address) - deGrandInitBalance)
      .to.equal(totalTransferAmount * 3 / 10); // 30%
    expect(await this.dehubToken.balanceOf(operator.address) - operatorInitBalance)
      .to.equal(totalTransferAmount / 10); // 10%

    /// Alpha is trying claimming non-closed lottery
    // Get ticket ids
    const userInfo = await this.standardLottery.connect(alpha).viewUserInfoForLotteryId(
      alpha.address,
      lotteryId,
      0, 100);
    const bracketIds = new Array(userInfo[0].length).fill(0);
    await expect(this.standardLottery.connect(alpha).claimTickets(
      lotteryId,
      userInfo[0],
      bracketIds
    )).to.be.revertedWith('Lottery not claimable');
  })

  describe("play game", async() => {
    beforeEach(async () => {
      const lotteryId = await this.standardLottery.viewCurrentTaskId();
      
      /// Buy tickets with 3 accounts
      // Buy ticket without bundle discount
      const alphaTickets = generateTicketNumbers(2);
      await this.dehubToken.connect(alpha).approve(this.standardLottery.address, DEHUB_PRICE * 2);
      await this.standardLottery.connect(alpha)
        .buyTickets(
          lotteryId,
          2, // purchased ticket count
          alphaTickets
        )
      // Buy ticket appliable to bundle
      const betaTickets = generateTicketNumbers(6);
      await this.dehubToken.connect(beta).approve(this.standardLottery.address, DEHUB_PRICE * 6);
      await this.standardLottery.connect(beta)
        .buyTickets(
          lotteryId,
          6, // purchased ticket count
          betaTickets // 6 purchased, 0 free
        );
      // Buy ticket appliable to bundle
      const gammaTickets = generateTicketNumbers(13);
      await this.dehubToken.connect(gamma).approve(this.standardLottery.address, DEHUB_PRICE * 10);
      await this.standardLottery.connect(gamma)
        .buyTickets(
          lotteryId,
          10, // purchased ticket count
          gammaTickets
        );

      /// Close Lottery
      await setBlockTime(lotteryEndTime);
      await this.standardLottery.connect(operator).closeLottery(lotteryId);

      /// Draw lottery
      await this.standardLottery.connect(operator).drawFinalNumber(lotteryId);
    })

    it("claim tickets", async () => {
      const lotteryId = await this.standardLottery.viewCurrentTaskId();

      // Claim tickets
      const userInfo = await this.standardLottery.connect(alpha).viewUserInfoForLotteryId(
        alpha.address,
        lotteryId,
        0, 100);
      const bracketIds = new Array(userInfo[0].length).fill(0);
      await this.standardLottery.connect(alpha).claimTickets(
        lotteryId,
        userInfo[0],
        bracketIds
      );

      // Check if there are not claimable tickets
      const userInfoAfterClaim = await this.standardLottery.connect(alpha).viewUserInfoForLotteryId(
        alpha.address,
        lotteryId,
        0, 100);
      let unclaimed = 0;
      userInfoAfterClaim[2].forEach(claimed => unclaimed |= !claimed);
      expect(unclaimed).to.equal(0);
    })

    it("transfer to", async () => {
      const initBalance = await this.dehubToken.balanceOf(operator.address);

      await this.standardLottery.transferTo(
        operator.address,
        DEHUB_PRICE
      );
      expect(await this.dehubToken.balanceOf(operator.address) - initBalance)
        .to.equal(DEHUB_PRICE);
    })

    it("burn", async () => {
      const lotteryId = await this.standardLottery.viewCurrentTaskId();

      await this.standardLottery.connect(operator).burnUnclaimed(lotteryId);
      expect(await this.dehubToken.balanceOf(this.standardLottery.address))
        .to.equal(0);
    })
  })
});
