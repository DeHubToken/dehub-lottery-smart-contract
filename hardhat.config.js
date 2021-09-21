require("dotenv").config();

require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-waffle");
require("hardhat-gas-reporter");
require("solidity-coverage");

const { mnemonic } = require('./secrets.json');

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: {
    version: "0.8.4",
    settings: {
      optimizer: {
        enabled: true
      }
    }
  },
	networks: {
		localhost: {
			url: 'http://127.0.0.1:8545',
			forking: {
				url: process.env.MORALIS_BSC_MAINNET_ARCHIVE_URL || '',
				blockNumber: 10553446,
			},
		},
		testnet: {
			url: process.env.MORALIS_BSC_TESTNET_ARCHIVE_URL || '',
			chainId: 97,
			gasPrice: 20000000000,
			accounts:
				process.env.DEPLOYER001_PRIVATE_KEY !== undefined
					? [process.env.DEPLOYER001_PRIVATE_KEY]
					: [],
		},
		mainnet: {
			url: process.env.MORALIS_BSC_MAINNET_URL || '',
			chainId: 56,
			gasPrice: 20000000000,
			accounts:
				process.env.DEPLOYER001_PRIVATE_KEY !== undefined
					? [process.env.DEPLOYER001_PRIVATE_KEY]
					: [],
		},
		hardhat: {
			initialBaseFeePerGas: 0, // workaround from https://github.com/sc-forks/solidity-coverage/issues/652#issuecomment-896330136 . Remove when that issue is closed.
		},
		ropsten: {
			url: process.env.ROPSTEN_URL || '',
			accounts:
				process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
		},
	},
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD",
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
};
