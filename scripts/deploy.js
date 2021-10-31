// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const { ethers, network, run, upgrades } = require("hardhat");
const { NomicLabsHardhatPluginError } = require("hardhat/plugins");

const addresses = {
  mainnet: {
    dehub: "0xFC206f429d55c71cb7294EfF40c6ADb20dC21508",
    randomGenerator: "0xd441586CeE8839C306aF40cae990D9f580bf1B64",
  },
  testnet: {
    dehub: "0x5A5e32fE118E7c7b6536d143F446269123c0ba74",
    randomGenerator: "0xA2355ED3bfDec475ff7b79C170A58E1B00fb5F2a",
  },
};

const chainLinkAddress = {
  testnet: {
    vrfCoordinator: "0xa555fC018435bef5A13C6c6870a9d4C11DEC329C",
    link: "0x84b9B910527Ad5C03A9Ca831909E21e236EA7b06",
    keyHash:
      "0xcaf3c3727e033261d383b315559476f48034c13b18f8cafed4d871abe5049186",
  },
};

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
    // We get the contract to deploy
    const StandardLottery = await ethers.getContractFactory("StandardLottery");
    const standardUpgrades = await upgrades.deployProxy(
      StandardLottery,
      [addresses[network.name].dehub, addresses[network.name].randomGenerator],
      {
        kind: "uups",
        initializer: "__StandardLottery_init",
      }
    );
    await standardUpgrades.deployed();

    await countTotalGas(standardUpgrades);
    console.log("Deployed StandardLottery contracts", { totalGas });

    const SpecialLottery = await ethers.getContractFactory("SpecialLottery");
    const specialUpgrades = await upgrades.deployProxy(
      SpecialLottery,
      [addresses[network.name].dehub, addresses[network.name].randomGenerator],
      {
        kind: "uups",
        initializer: "__SpecialLottery_init",
      }
    );
    await specialUpgrades.deployed();

    await countTotalGas(specialUpgrades);
    console.log("Deployed SpecialLottery contracts", { totalGas });

    console.log("StandardLottery deployed to:", standardUpgrades.address);
    console.log("SpecialLottery deployed to:", specialUpgrades.address);

    console.log(">>>>>>>>>>>> Verification >>>>>>>>>>>>");

    try {
      // Verify
      const standardImpl = await upgrades.erc1967.getImplementationAddress(
        standardUpgrades.address
      );
      console.log("Verifying standard address: ", standardImpl);
      await run("verify:verify", {
        address: standardImpl,
      });
    } catch (error) {
      if (error instanceof NomicLabsHardhatPluginError) {
        console.log("Contract source code already verified");
      } else {
        console.error(error);
      }
    }

    try {
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

    // Set configuration on StandardLottery
    await standardUpgrades.setOperatorAddress(process.env.OPERATOR_ADDRESS);
    console.log(
      `Set operator of StandardLottery: ${process.env.OPERATOR_ADDRESS}`
    );
    await standardUpgrades.setDeGrandAddress(specialUpgrades.address);
    console.log(`Set DeGrand of StandardLottery: ${specialUpgrades.address}`);
    await standardUpgrades.setTeamWallet(process.env.TEAM_WALLET);
    console.log(
      `Set team wallet of StandardLottery: ${process.env.TEAM_WALLET}`
    );

    // Set configuration on SpecialLottery
    await specialUpgrades.setOperatorAddress(process.env.OPERATOR_ADDRESS);
    console.log(
      `Set operator of SpecialLottery: ${process.env.OPERATOR_ADDRESS}`
    );
    await specialUpgrades.setDeLottoAddress(standardUpgrades.address);
    console.log(`Set DeLotto of SpecialLottery: ${standardUpgrades.address}`);
    await specialUpgrades.setTeamWallet(process.env.TEAM_WALLET);
    console.log(
      `Set team wallet of SpecialLottery: ${process.env.TEAM_WALLET}`
    );

    // Change transferer address of StandardLottery
    await standardUpgrades.setTransfererAddress(specialUpgrades.address);
    console.log(
      `Set transferer address of StandardLottery: ${specialUpgrades.address}`
    );

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
        Label: "StandardLottery",
        Info: standardUpgrades.address,
      },
      {
        Label: "SpecialLottery",
        Info: specialUpgrades.address,
      },
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
