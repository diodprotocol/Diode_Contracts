const hre = require("hardhat");
const { ethers } = require("hardhat");


const dio1Polygon = "0xf27ac523cbaf040dac61d1a9845d6cb84d213d12"
const wmaticToken = "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270"
let user1;
const provider = ethers.provider;

const dio1_abi = ['function depositFunds(uint256,bool) public returns (uint256,uint256,uint256,uint256)',
'function totalDeposits() public returns (uint256)'];
const wmatic_abi = ['function approve(address,uint256) public returns (bool)'];




async function depositDIO1 (){

    [user1, _] = await ethers.getSigners();

    const wmaticContract = new ethers.Contract(wmaticToken, wmatic_abi, user1)
    const dio1Contract = new ethers.Contract(dio1Polygon, dio1_abi, user1)
    
    const tx1 = await wmaticContract.approve(dio1Polygon, BigInt(1000000000000000000));
    await tx1.wait();

    console.log("wmatic approved");

    const tx2 = await dio1Contract.depositFunds(BigInt(1000000000000000000), true);
    await tx2.wait();

    console.log(tx2);

    const totalDeposits = await dio1Contract.totalDeposits();

    console.log(totalDeposits);

}


async function main(){
    await depositDIO1();
}


main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
