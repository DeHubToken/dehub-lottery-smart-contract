const { expect } = require("chai");
const { ethers } = require("hardhat");
const { now, increaseTime, setBlockTime } = require("./utils/common");

describe("SpecialLottery", () => {

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

    this.dehubToken = await DehubToken.deploy("Dehub", "$Dehub", 100000000);
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

    await this.dehubToken.transfer(alpha.address, 10000000);
    await this.dehubToken.transfer(beta.address, 10000000);
    await this.dehubToken.transfer(gamma.address, 10000000);
    
    /// Initialize Lottery
    // Set operator address
    await this.specialLottery.setOperatorAddress(operator.address);
    // Set DeGrand address
    await this.specialLottery.setDeLottoAddress(this.standardLottery.address);
    // Set team address
    await this.specialLottery.setTeamWallet(operator.address);
    // Set breakdown percent
    await this.specialLottery.setBreakdownPercent(
      7000, // DeLotto pot
      2000, // Team Wallet
      1000  // Burn
    );
    
    await this.standardLottery.transferOwnership(this.specialLottery.address);

    /// Start Lottery
    lotteryStartTime = await now();
    lotteryEndTime = lotteryStartTime + SIX_HOUR;
    await this.specialLottery.connect(operator).startLottery(
      lotteryEndTime, // lottery endtime
      DEHUB_PRICE // price in $Dehub
    );
  })

  it("start/close lottery", async () => {
    // Close lottery before 6 hours, will occur error
    const lotteryId = await this.specialLottery.viewCurrentTaskId();

    await expect(this.specialLottery.connect(operator).closeLottery(lotteryId))
      .to.be.revertedWith('Lottery not over');

    // Pass 6 hours
    await increaseTime(SIX_HOUR);

    // Close lottery again
    await this.specialLottery.connect(operator).closeLottery(lotteryId);

    // Check lottery information
    const {
      status
    } = await this.specialLottery.viewLottery(lotteryId);
    expect(status).to.equal(2); // Close
  })

  it("buy tickets", async () => {
    const lotteryId = await this.specialLottery.viewCurrentTaskId();

    const deLottoInitBalance = await this.dehubToken.balanceOf(this.standardLottery.address);
    const deGrandInitBalance = await this.dehubToken.balanceOf(this.specialLottery.address);
    const operatorInitBalance = await this.dehubToken.balanceOf(operator.address);

    const alphaInitBalance = await this.dehubToken.balanceOf(alpha.address);
    const betaInitBalance = await this.dehubToken.balanceOf(beta.address);
    const gammaInitBalance = await this.dehubToken.balanceOf(gamma.address);

    /// Buy tickets with 3 accounts
    await this.dehubToken.connect(alpha).approve(this.specialLottery.address, DEHUB_PRICE * 50);
    await this.specialLottery.connect(alpha)
      .buyTickets(
        lotteryId,
        50 // purchased ticket count
      );
    await this.dehubToken.connect(beta).approve(this.specialLottery.address, DEHUB_PRICE * 40);
    await this.specialLottery.connect(beta)
      .buyTickets(
        lotteryId,
        40 // purchased ticket count
      );
    await this.dehubToken.connect(gamma).approve(this.specialLottery.address, DEHUB_PRICE * 30);
    await this.specialLottery.connect(gamma)
      .buyTickets(
        lotteryId,
        30 // purchased ticket count
      );

    /// Check buyer's token amount
    expect(alphaInitBalance - await this.dehubToken.balanceOf(alpha.address))
      .to.equal(DEHUB_PRICE * 50);
    expect(betaInitBalance - await this.dehubToken.balanceOf(beta.address))
      .to.equal(DEHUB_PRICE * 40);
    expect(gammaInitBalance - await this.dehubToken.balanceOf(gamma.address))
      .to.equal(DEHUB_PRICE * 30);

    const totalTransferAmount = DEHUB_PRICE * (50+40+30);

    // Check if token was transfered to DeLotto, team, dead
    expect(await this.dehubToken.balanceOf(this.standardLottery.address) - deLottoInitBalance)
      .to.equal(totalTransferAmount * 7 / 10); // 70%
    expect(await this.dehubToken.balanceOf(operator.address) - operatorInitBalance)
      .to.equal(totalTransferAmount / 5); // 20%

    /// Alpha is trying claimming non-closed lottery
    // Get ticket ids
    const userInfo = await this.specialLottery.connect(alpha).viewUserInfoForLotteryId(
      alpha.address,
      lotteryId,
      0, 100);
    await expect(this.specialLottery.connect(alpha).claimTickets(
      lotteryId,
      userInfo[0]
    )).to.be.revertedWith('Lottery not claimable');
  })

  describe("play game", async () => {
    beforeEach(async () => {
      const lotteryId = await this.specialLottery.viewCurrentTaskId();

      /// Buy tickets with 3 accounts
      await this.dehubToken.connect(alpha).approve(this.specialLottery.address, DEHUB_PRICE * 2);
      await this.specialLottery.connect(alpha)
        .buyTickets(
          lotteryId,
          2 // purchased ticket count
        );
      await this.dehubToken.connect(beta).approve(this.specialLottery.address, DEHUB_PRICE * 3);
      await this.specialLottery.connect(beta)
        .buyTickets(
          lotteryId,
          3 // purchased ticket count
        );
      await this.dehubToken.connect(gamma).approve(this.specialLottery.address, DEHUB_PRICE * 4);
      await this.specialLottery.connect(gamma)
        .buyTickets(
          lotteryId,
          4 // purchased ticket count
        );

      /// Close Lottery
      await setBlockTime(lotteryEndTime);
      await this.specialLottery.connect(operator).closeLottery(lotteryId);
    })

    it("pick delotto second stage", async () => {
      const lotteryId = await this.specialLottery.viewCurrentTaskId();

      const alphaInitBalance = await this.dehubToken.balanceOf(alpha.address);
      const unwonPot = await this.dehubToken.balanceOf(this.standardLottery.address);

      await this.specialLottery.connect(operator).pickAwardWinners(lotteryId);

      const userInfo = await this.specialLottery.connect(alpha).viewUserInfoForLotteryId(
        alpha.address,
        lotteryId,
        0, 100);
      await this.specialLottery.connect(alpha).claimTickets(
        lotteryId,
        userInfo[0]
      );
      expect(await this.dehubToken.balanceOf(alpha.address) - alphaInitBalance)
        .to.equal(unwonPot * 2 / 100); // 1% * 2 tickets
    })

    it("pick degrand stage", async () => {
      const lotteryId = await this.specialLottery.viewCurrentTaskId();

      await this.specialLottery.pickDeGrandWinners(lotteryId, 9);

      const deGrandInfo = await this.specialLottery.connect(alpha)
        .viewDeGrandStatusForTicketIds(
          lotteryId
        );
      expect(deGrandInfo[0].length).to.gte(0); // more than 1 or equal
    })
  })

  it("transfer to", async () => {
    await this.dehubToken.transfer(this.specialLottery.address, DEHUB_PRICE);

    const initBalance = await this.dehubToken.balanceOf(operator.address);

    await this.specialLottery.transferTo(
      operator.address,
      DEHUB_PRICE
    );
    expect(await this.dehubToken.balanceOf(operator.address) - initBalance)
      .to.equal(DEHUB_PRICE);
  })
  
});
