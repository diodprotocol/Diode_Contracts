require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();
require("@nomiclabs/hardhat-etherscan");


/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.16",
    settings: {
      optimizer: {
        enabled: true,
        runs: 1000,
      }
    }
  },


  networks: {
    goerli: {
      url: process.env.ALCHEMY_GOERLI,
      accounts: [process.env.PRIVATE_KEY],
      gas: "auto",
    }
  },

  etherscan: {
    apiKey: process.env.ETHERSCAN_API
  },
};