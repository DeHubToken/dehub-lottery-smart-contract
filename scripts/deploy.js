// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const { ethers, network, run, upgrades } = require("hardhat");



const addresses = {
  mainnet: {
    dehub: "0xFC206f429d55c71cb7294EfF40c6ADb20dC21508",
    randomGenerator: ""
  },
  testnet: {
    dehub: "0x5A5e32fE118E7c7b6536d143F446269123c0ba74",
    randomGenerator: "0xB92D99cfDb06Fef8F9C528C06a065012Fd44686D"
  }
}

const chainLinkAddress = {
  testnet: {
    vrfCoordinator: "0xa555fC018435bef5A13C6c6870a9d4C11DEC329C",
    link: "0x84b9B910527Ad5C03A9Ca831909E21e236EA7b06",
    keyHash: "0xcaf3c3727e033261d383b315559476f48034c13b18f8cafed4d871abe5049186"
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
    const RandomNumberGenerator = await ethers.getContractFactory("RandomNumberGenerator");
    const randomNumberGenerator = await RandomNumberGenerator.connect(deployer).deploy(
      chainLinkAddress[network.name].vrfCoordinator,
      chainLinkAddress[network.name].link
    );
    await randomNumberGenerator.deployed();
    randomNumberGenerator.connect(deployer).setKeyHash(
      chainLinkAddress[network.name].keyHash
    );

    const StandardLottery = await ethers.getContractFactory("StandardLottery");
    const standardUpgrades = await upgrades.deployProxy(StandardLottery, [
      addresses[network.name].dehub,
      randomNumberGenerator.address, // addresses[network.name].randomGenerator
    ], {
      kind: 'uups',
      initializer: '__StandardLottery_init'
    });
    await standardUpgrades.deployed();
    
    const SpecialLottery = await ethers.getContractFactory("SpecialLottery");
    const specialUpgrades = await upgrades.deployProxy(SpecialLottery, [
      addresses[network.name].dehub,
      randomNumberGenerator.address, // addresses[network.name].randomGenerator
    ], {
      initializer: '__SpecialLottery_init',
      kind: 'uups'
    });

    console.log("RandomNumberGenerator deployed to:", randomNumberGenerator.address);
    console.log("StandardLottery deployed to:", standardLottery.address);
    console.log("SpecialLottery deployed to:", specialLottery.address);

    // Verify
    await run("verify:verify", {
      address: randomNumberGenerator.address,
      constructorArguments: [
        chainLinkAddress[network.name].vrfCoordinator,
        chainLinkAddress[network.name].link
      ]
    });
    const standardImpl = await upgrades.erc1967.getImplementationAddress(
      standardUpgrades.address
    );
    await run("verify:verify", {
      address: standardImpl,
      constructorArguments: [
        addresses[network.name].dehub,
        randomNumberGenerator.address, // addresses[network.name].randomGenerator
      ]
    });
    const specialImpl = await upgrades.erc1967.getImplementationAddress(
      specialUpgrades.address
    );
    await run("verify:verify", {
      address: specialImpl,
      constructorArguments: [
        addresses[network.name].dehub,
        randomNumberGenerator.address, // addresses[network.name].randomGenerator
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

    // Change transferer address of StandardLottery
    await standardLottery.connect(deployer).setTransfererAddress(specialLottery.address);
    console.log(`Set transferer address of StandardLottery: ${specialLottery.address}`);

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
