// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const { ethers } = require("hardhat");
const hre = require("hardhat");

async function main() {

  const DiodeFactoryAll1 = await hre.ethers.getContractFactory("DiodeFactoryAll1");
  const diodeFactoryAll1 = await DiodeFactoryAll1.deploy();

  await diodeFactoryAll1.deployed();

  console.log("diodeFactoryAll1 deployed to", diodeFactoryAll1.address); 

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
