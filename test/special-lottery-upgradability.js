const { BigNumber } = require("@ethersproject/bignumber");
const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const { now, increaseTime, setBlockTime } = require("./utils/common");

const upgradeInstanceToV2 = async (admin, addressV1) => {
  const SpecialLotteryV2 = await ethers.getContractFactory(
    "SpecialLotteryV2",
    admin
  );

  const specialLotteryV2 = await upgrades.upgradeProxy(
    addressV1,
    SpecialLotteryV2
  );
  specialLotteryV2.upgradeToV2();
  return specialLotteryV2;
};

const upgradeInstanceToV3 = async (admin, addressV2) => {
  const SpecialLotteryV3 = await ethers.getContractFactory(
    "SpecialLotteryV3",
    admin
  );

  const specialLotteryV3 = await upgrades.upgradeProxy(
    addressV2,
    SpecialLotteryV3
  );
  specialLotteryV3.upgradeToV3();
  return specialLotteryV3;
};

const upgradeInstanceToV4 = async (admin, addressV3) => {
  const SpecialLotteryV4 = await ethers.getContractFactory(
    "SpecialLotteryV4",
    admin
  );

  const specialLotteryV4 = await upgrades.upgradeProxy(
    addressV3,
    SpecialLotteryV4
  );
  specialLotteryV4.upgradeToV4();
  return specialLotteryV4;
};

describe("SpecialLottery-upgradability", () => {
  const DEHUB_PRICE = 1000 * 100000;
  const SIX_HOUR = 3600 * 6;

  let admin, operator;
  let addrs;

  let lotteryStartTime, lotteryEndTime;

  beforeEach(async () => {
    [admin, operator, ...addrs] = await ethers.getSigners();

    const DehubToken = await ethers.getContractFactory("MockERC20", admin);
    const DehubRandom = await ethers.getContractFactory("MockDehubRand", admin);
    const StandardLottery = await ethers.getContractFactory(
      "StandardLottery",
      admin
    );
    const StandardLotteryV2 = await ethers.getContractFactory(
      "StandardLotteryV2",
      admin
    );
    const SpecialLottery = await ethers.getContractFactory(
      "SpecialLottery",
      admin
    );
    const SpecialLotteryV2 = await ethers.getContractFactory(
      "SpecialLotteryV2",
      admin
    );

    this.dehubToken = await DehubToken.deploy(
      "Dehub",
      "$Dehub",
      BigNumber.from("10000000000000")
    );
    await this.dehubToken.deployed();
    this.dehubRandom = await DehubRandom.deploy();
    await this.dehubRandom.deployed();
    this.standardLotteryV1 = await upgrades.deployProxy(
      StandardLottery,
      [this.dehubToken.address, this.dehubRandom.address],
      {
        kind: "uups",
        initializer: "__StandardLottery_init",
      }
    );
    await this.standardLotteryV1.deployed();
    this.standardLottery = await upgrades.upgradeProxy(
      this.standardLotteryV1.address,
      StandardLotteryV2
    );
    await this.standardLottery.upgradeToV2();
    this.specialLotteryV1 = await upgrades.deployProxy(
      SpecialLottery,
      [this.dehubToken.address, this.dehubRandom.address],
      {
        kind: "uups",
        initializer: "__SpecialLottery_init",
      }
    );
    await this.specialLotteryV1.deployed();
    this.specialLottery = await upgrades.upgradeProxy(
      this.specialLotteryV1.address,
      SpecialLotteryV2
    );
    await this.specialLottery.upgradeToV2();

    for (let idx = 0; idx < addrs.length; idx++) {
      await this.dehubToken.transfer(
        addrs[idx].address,
        BigNumber.from("100000000000")
      );
    }

    /// Initialize Lottery
    // Set operator address
    await this.specialLottery.setOperatorAddress(operator.address);
    // Set DeLotto address
    await this.specialLottery.setDeLottoAddress(this.standardLottery.address);
    // Set team address
    await this.specialLottery.setTeamWallet(operator.address);
    // Set breakdown percent
    await this.specialLottery.setBreakdownPercent(
      7000, // DeLotto pot
      0, // DeGrand pot
      2000, // Team Wallet
      1000 // Burn
    );

    await this.standardLottery.setTransfererAddress(
      this.specialLottery.address
    );

    /// Start Lottery
    lotteryStartTime = await now();
    lotteryEndTime = lotteryStartTime + SIX_HOUR;
    await this.specialLottery.connect(operator).startLottery(
      lotteryEndTime, // lottery endtime
      DEHUB_PRICE // price in $Dehub
    );
  });

  it("Should upgrade to V3.", async () => {
    // Check V2
    expect(await this.specialLottery.version()).to.equal(2);

    // Check V3
    const specialLotteryV3 = await upgradeInstanceToV3(
      admin.address,
      this.specialLottery.address
    );
    expect(await specialLotteryV3.version()).to.equal(3);
  });

  it("Should upgrade to V4.", async () => {
    // Check V2
    expect(await this.specialLottery.version()).to.equal(2);

    // Check V3
    const specialLotteryV3 = await upgradeInstanceToV3(
      admin.address,
      this.specialLottery.address
    );
    expect(await specialLotteryV3.version()).to.equal(3);

    // Check V4
    const specialLotteryV4 = await upgradeInstanceToV4(
      admin.address,
      specialLotteryV3.address
    );
    expect(await specialLotteryV4.version()).to.equal(4);
  });

  it("user tickets must be preserved", async () => {
    const lotteryId = await this.specialLottery.viewCurrentTaskId();

    const alphaInitBalance = [];

    /// Buy tickets
    for (let idx = 0; idx < addrs.length; idx++) {
      alphaInitBalance.push(
        await this.dehubToken.balanceOf(addrs[idx].address)
      );
      await this.dehubToken
        .connect(addrs[idx])
        .approve(this.specialLottery.address, DEHUB_PRICE * 50);
      await this.specialLottery.connect(addrs[idx]).buyTickets(
        lotteryId,
        50 // purchased ticket count
      );
    }

    const specialLotteryV3 = await upgradeInstanceToV3(
      admin.address,
      this.specialLottery.address
    );

    /// Check buyer's token amount
    for (let idx = 0; idx < addrs.length; idx++) {
      expect(
        alphaInitBalance[idx] -
          (await this.dehubToken.balanceOf(addrs[idx].address))
      ).to.equal(DEHUB_PRICE * 50);
      // Get ticket ids
      const userInfo = await specialLotteryV3
        .connect(addrs[idx])
        .viewUserInfoForLotteryId(addrs[idx].address, lotteryId, 0, 100);
      expect(userInfo[0].length).to.equal(50);
    }
  });

  it("prize pot must be preserved", async () => {
    const lotteryId = await this.specialLottery.viewCurrentTaskId();

    /// Buy tickets
    for (let idx = 0; idx < addrs.length; idx++) {
      await this.dehubToken
        .connect(addrs[idx])
        .approve(this.specialLottery.address, DEHUB_PRICE * 50);
      await this.specialLottery.connect(addrs[idx]).buyTickets(
        lotteryId,
        50 // purchased ticket count
      );
    }

    const specialLotteryV3 = await upgradeInstanceToV3(
      admin.address,
      this.specialLottery.address
    );

    /// Check balance
    const beforeIncreasePot = await this.dehubToken.balanceOf(
      specialLotteryV3.address
    );

    /// Increase pot by previous contract instance
    await this.dehubToken.approve(specialLotteryV3.address, 3000);
    await specialLotteryV3.increasePot(lotteryId, 3000);

    expect(
      (await this.dehubToken.balanceOf(specialLotteryV3.address)) -
        beforeIncreasePot
    ).to.equal(3000);
  });

  it("degrand prize must be preserved", async () => {
    const lotteryId = await this.specialLottery.viewCurrentTaskId();

    const nowTime = (await now()) + 1000;

    await this.specialLottery.setDeGrandPrize(
      nowTime,
      "title",
      "subtitle",
      "description",
      "ctaUrl",
      "imageUrl",
      1
    );

    const specialLotteryV3 = await upgradeInstanceToV3(
      admin.address,
      this.specialLottery.address
    );

    const {
      drawTime,
      title,
      subtitle,
      description,
      ctaUrl,
      imageUrl,
      maxWinnerCount,
      picked,
    } = await specialLotteryV3.viewDeGrandPrizeByLotteryId(lotteryId);

    expect(drawTime).to.equal(nowTime);
    expect(title).to.equal("title");
    expect(subtitle).to.equal("subtitle");
    expect(description).to.equal("description");
    expect(ctaUrl).to.equal("ctaUrl");
    expect(imageUrl).to.equal(imageUrl);
    expect(maxWinnerCount).to.equal(1);
    expect(picked).to.equal(false);
  });

  describe("degrand picked winners", async () => {
    beforeEach(async () => {
      const lotteryId = await this.specialLottery.viewCurrentTaskId();

      this.specialLotteryV3 = await upgradeInstanceToV3(
        admin.address,
        this.specialLottery.address
      );

      /// Buy tickets
      for (let idx = 0; idx < addrs.length; idx++) {
        await this.dehubToken
          .connect(addrs[idx])
          .approve(this.specialLotteryV3.address, DEHUB_PRICE * 50);
        await this.specialLotteryV3.connect(addrs[idx]).buyTickets(
          lotteryId,
          50 // purchased ticket count
        );
      }

      /// Close Lottery
      await setBlockTime(lotteryEndTime);
      await this.specialLotteryV3.connect(operator).closeLottery(lotteryId);
    });

    it("only 1 maximum winners should be picked", async () => {
      const lotteryId = await this.specialLotteryV3.viewCurrentTaskId();

      const nowTime = (await now()) + 1000;

      await this.specialLotteryV3.setDeGrandPrize(
        nowTime,
        "title",
        "subtitle",
        "description",
        "ctaUrl",
        "imageUrl",
        1
      );

      await this.specialLotteryV3.pickDeGrandWinners(lotteryId);

      const deGrandStatus =
        await this.specialLotteryV3.viewDeGrandStatusForTicketIds(lotteryId);
      expect(deGrandStatus[0].length).to.equal(1); // number of winner address
      expect(deGrandStatus[1].length).to.equal(1); // number of winning tickets
    });

    it("more than 1 maximum winners should be picked", async () => {
      const lotteryId = await this.specialLotteryV3.viewCurrentTaskId();

      const nowTime = (await now()) + 1000;

      await this.specialLotteryV3.setDeGrandPrize(
        nowTime,
        "title",
        "subtitle",
        "description",
        "ctaUrl",
        "imageUrl",
        10
      );

      await this.specialLotteryV3.pickDeGrandWinners(lotteryId);

      const deGrandStatus =
        await this.specialLotteryV3.viewDeGrandStatusForTicketIds(lotteryId);
      console.log("deGrandStatusd", deGrandStatus);
      for (let idx = 0; idx < addrs.length; idx++) {
        console.log("addrs[idx]", addrs[idx].address);
      }

      expect(deGrandStatus[0].length).to.equal(10); // number of winner address
      expect(deGrandStatus[1].length).to.equal(10); // number of winning tickets
    });
  });

  describe("delotto second stage picked winners", async () => {
    beforeEach(async () => {
      const lotteryId = await this.specialLottery.viewCurrentTaskId();

      this.specialLotteryV3 = await upgradeInstanceToV3(
        admin.address,
        this.specialLottery.address
      );

      /// Buy tickets
      for (let idx = 0; idx < addrs.length; idx++) {
        await this.dehubToken
          .connect(addrs[idx])
          .approve(this.specialLotteryV3.address, DEHUB_PRICE * 100);
        await this.specialLotteryV3.connect(addrs[idx]).buyTickets(
          lotteryId,
          50 // purchased ticket count
        );
      }

      /// Close Lottery
      await setBlockTime(lotteryEndTime);
      await this.specialLotteryV3.connect(operator).closeLottery(lotteryId);
    });

    it("maximum winning ticket is 100, more than 50", async () => {
      const lotteryId = await this.specialLottery.viewCurrentTaskId();

      await this.specialLotteryV3.connect(operator).pickAwardWinners(lotteryId);

      let totalWinnings = 0;

      // Checking winning tickets
      for (let idx = 0; idx < addrs.length; idx++) {
        const userInfo = await this.specialLotteryV3
          .connect(addrs[idx])
          .viewUserInfoForLotteryId(addrs[idx].address, lotteryId, 0, 100);
        const winningStatus =
          await this.specialLotteryV3.viewDeLottoWinningForTicketIds(
            lotteryId,
            userInfo[0] // ticket ids
          );
        for (let idx2 = 0; idx2 < winningStatus.length; idx2++) {
          totalWinnings += winningStatus[idx2] ? 1 : 0;
        }
      }

      console.log("totalWinnings", totalWinnings);
      expect(totalWinnings).to.greaterThanOrEqual(50);
      expect(totalWinnings).to.lessThanOrEqual(100);
    });
  });

  it("change ticket rate", async () => {
    const lotteryId = await this.specialLottery.viewCurrentTaskId();

    const specialLotteryV3 = await upgradeInstanceToV3(
      admin.address,
      this.specialLottery.address
    );

    const newPrice = 2000 * 100000;
    await specialLotteryV3.changeTicketRate(newPrice);

    const { ticketRate } = await specialLotteryV3.viewLottery(lotteryId);
    expect(ticketRate).to.equal(newPrice);
  });

  it("decrease ticket rate", async () => {
    const lotteryId = await this.specialLottery.viewCurrentTaskId();

    const specialLotteryV3 = await upgradeInstanceToV3(
      admin.address,
      this.specialLottery.address
    );

    const initBalance = await this.dehubToken.balanceOf(addrs[0].address);

    const newPrice = 500 * 100000;
    await specialLotteryV3.changeTicketRate(newPrice);

    await this.dehubToken
      .connect(addrs[0])
      .approve(specialLotteryV3.address, newPrice * 50);

    await specialLotteryV3.connect(addrs[0]).buyTickets(
      lotteryId,
      50 // purchased ticket count
    );

    expect(
      initBalance - (await this.dehubToken.balanceOf(addrs[0].address))
    ).to.equal(newPrice * 50);

    // Get ticket ids
    const userInfo = await specialLotteryV3
      .connect(addrs[0])
      .viewUserInfoForLotteryId(addrs[0].address, lotteryId, 0, 100);
    expect(userInfo[0].length).to.equal(50);
  });

  // it("increase ticket rate", async () => {
  //   const lotteryId = await this.specialLottery.viewCurrentTaskId();

  //   const specialLotteryV3 = await upgradeInstanceToV3(
  //     admin.address,
  //     this.specialLottery.address
  //   );

  //   const newPrice = 2000 * 100000;
  //   await specialLotteryV3.changeTicketRate(newPrice);

  //   await this.dehubToken
  //     .connect(addrs[0])
  //     .approve(this.specialLotteryV3.address, DEHUB_PRICE * 50);

  //   await expect(this.specialLotteryV3.connect(addrs[idx]).buyTickets(
  //     lotteryId,
  //     50 // purchased ticket count
  //   ).to.be.reverted();
  // });
});
