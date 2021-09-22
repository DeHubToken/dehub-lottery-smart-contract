// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const { ethers } = require("hardhat");

async function main() {
  const dehub = '0xD3b5134fef18b69e1ddB986338F2F80CD043a1AF';
  const randomGenerator = '0xD3b5134fef18b69e1ddB986338F2F80CD043a1AF';

  const [deployer] = await ethers.getSigners();

  console.log(
    "Deploying contracts with the account:",
    deployer.address
  );

  // We get the contract to deploy
  const StandardLottery = await ethers.getContractFactory("StandardLottery");
  const standardLottery = await StandardLottery.deploy(dehub, randomGenerator);
  await standardLottery.deployed();
  
  const SpecialLottery = await ethers.getContractFactory("SpecialLottery");
  const specialLottery = await SpecialLottery.deploy(dehub, randomGenerator);
  await specialLottery.deployed();

  console.log("StandardLottery deployed to:", standardLottery.address);
  console.log("SpecialLottery deployed to:", specialLottery.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
