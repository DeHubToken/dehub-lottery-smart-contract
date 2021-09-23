// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const { ethers, network, run } = require("hardhat");

const addresses = {
  mainnet: {
    dehub: "0xFC206f429d55c71cb7294EfF40c6ADb20dC21508",
    randomGenerator: ""
  },
  testnet: {
    dehub: "0xFC206f429d55c71cb7294EfF40c6ADb20dC21508",
    randomGenerator: "0xB92D99cfDb06Fef8F9C528C06a065012Fd44686D"
  }
}

async function main() {
  const signers = await ethers.getSigners();

  let deployer;
  signers.forEach(signer => {
    if (signer.address === process.env.DEPLOYER001) {
      deployer = signer;
    }
  })
  if (!deployer) {
		throw new Error(`${process.env.DEPLOYER001} not found in signers!`);
  }

  console.log(
    "Deploying contracts with the account:",
    deployer.address
  );
  console.log("Network:", network.name);

  if (network.name === "testnet" || network.name === "mainnet") {
    // We get the contract to deploy
    const StandardLottery = await ethers.getContractFactory("StandardLottery");
    const standardLottery = await StandardLottery.connect(deployer).deploy(
      addresses[network.name].dehub,
      addresses[network.name].randomGenerator
    );
    await standardLottery.deployed();
    
    const SpecialLottery = await ethers.getContractFactory("SpecialLottery");
    const specialLottery = await SpecialLottery.connect(deployer).deploy(
      addresses[network.name].dehub,
      addresses[network.name].randomGenerator
    );
    await specialLottery.deployed();

    console.log("StandardLottery deployed to:", standardLottery.address);
    console.log("SpecialLottery deployed to:", specialLottery.address);

    // Verify
    await run("verify:verify", {
      address: standardLottery.address,
      constructorArguments: [
        addresses[network.name].dehub,
        addresses[network.name].randomGenerator
      ]
    });
    await run("verify:verify", {
      address: specialLottery.address,
      constructorArguments: [
        addresses[network.name].dehub,
        addresses[network.name].randomGenerator
      ]
    });

    // Set configuration on StandardLottery
    await standardLottery.connect(deployer).setOperatorAddress(process.env.OPERATOR_ADDRESS);
    console.log(`Set operator of StandardLottery: ${process.env.OPERATOR_ADDRESS}`);
    await standardLottery.connect(deployer).setDeGrandAddress(specialLottery.address);
    console.log(`Set DeGrand of StandardLottery: ${specialLottery.address}`);
    await standardLottery.connect(deployer).setTeamWallet(process.env.TEAM_WALLET);
    console.log(`Set team wallet of StandardLottery: ${process.env.TEAM_WALLET}`);

    // Set configuration on SpecialLottery
    await specialLottery.connect(deployer).setOperatorAddress(process.env.OPERATOR_ADDRESS);
    console.log(`Set operator of SpecialLottery: ${process.env.OPERATOR_ADDRESS}`);
    await specialLottery.connect(deployer).setDeLottoAddress(standardLottery.address);
    console.log(`Set DeLotto of SpecialLottery: ${standardLottery.address}`);
    await specialLottery.connect(deployer).setTeamWallet(process.env.TEAM_WALLET);
    console.log(`Set team wallet of SpecialLottery: ${process.env.TEAM_WALLET}`);

    // Change owner of StandardLottery
    await standardLottery.connect(deployer).transferOwnership(specialLottery.address);
    console.log(`Set ownership of StandardLottery: ${specialLottery.address}`);

    // Logging out in table format
    console.table([
      {
        Label: 'Deploying Address',
        Info: deployer.address
      },
      {
        Label: 'Deployer BNB Balance',
        Info: ethers.utils.formatEther(await deployer.getBalance())
      },
      {
        Label: 'StandardLottery',
        Info: standardLottery.address
      },
      {
        Label: 'SpecialLottery',
        Info: specialLottery.address
      }
    ])
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
