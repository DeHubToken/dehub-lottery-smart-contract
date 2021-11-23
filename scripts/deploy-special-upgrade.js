const { ethers, network, run, upgrades } = require("hardhat");
const { NomicLabsHardhatPluginError } = require("hardhat/plugins");
const manifestInMainnet = require("../.openzeppelin/unknown-56.json");
const manifestInTestnet = require("../.openzeppelin/unknown-97.json");

/**
 * Upgrade contract to the new latest version.
 * Environment: Local.
 * ! TODO before each execution:
 * * 1. Update factory name to your latest one.
 * * 2. Make sure proxy address is the correct one.
 * * 3. Update `upgradeTo{}()` function to the latest one.
 * ! Note: DO NOT delete in mainnet './openzeppelin/unknown-56.json'
 * ! Note: DO NOT delete in testnet './openzeppelin/unknown-97.json'
 */

let totalGas = 0;
const countTotalGas = async (tx) => {
  let res = tx;
  if (tx.deployTransaction) tx = tx.deployTransaction;
  if (tx.wait) res = await tx.wait();
  if (res.gasUsed) totalGas += parseInt(res.gasUsed);
  else console.log("no gas data", { res, tx });
};

async function main() {
  const signers = await ethers.getSigners();
  // Find deployer signer in signers.
  let deployer;
  signers.forEach((a) => {
    if (a.address === process.env.DEPLOYER001) {
      deployer = a;
    }
  });
  if (!deployer) {
    throw new Error(`${process.env.DEPLOYER001} not found in signers!`);
  }

  console.log("Deploying contracts with the account:", deployer.address);
  console.log("Network:", network.name);

  if (network.name === "testnet" || network.name === "mainnet") {
    // Deploy special contract
    const specialLotteryV1 =
      network.name === "testnet"
        ? manifestInTestnet.proxies[1].address
        : manifestInMainnet.proxies[1].address;

    console.log('specialLotteryV1', specialLotteryV1);

    // We get the contract to deploy
    const SpecialLotteryV2 = await ethers.getContractFactory(
      "SpecialLotteryV2"
    );
    const specialUpgrades = await upgrades.upgradeProxy(
      specialLotteryV1,
      SpecialLotteryV2
    );
    await specialUpgrades.deployed();
    await specialUpgrades.upgradeToV2();

    await countTotalGas(specialUpgrades);
    console.log("Deployed SpecialLotteryV2 contracts", { totalGas });
    console.log("SpecialLottery deployed to:", specialUpgrades.address);

    console.log(">>>>>>>>>>>> Verification >>>>>>>>>>>>");

    try {
      // Verify
      const specialImpl = await upgrades.erc1967.getImplementationAddress(
        specialUpgrades.address
      );
      console.log("Verifying special address: ", specialImpl);
      await run("verify:verify", {
        address: specialImpl,
      });
    } catch (error) {
      if (error instanceof NomicLabsHardhatPluginError) {
        console.log("Contract source code already verified");
      } else {
        console.error(error);
      }
    }

    console.log(">>>>>>>>>>>> Configuration >>>>>>>>>>>>");

    // Logging out in table format
    console.table([
      {
        Label: "Deploying Address",
        Info: deployer.address,
      },
      {
        Label: "Deployer BNB Balance",
        Info: ethers.utils.formatEther(await deployer.getBalance()),
      },
      {
        Label: "SpecialLottery",
        Info: specialUpgrades.address,
      }
    ]);
  }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
