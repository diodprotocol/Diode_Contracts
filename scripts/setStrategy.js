const hre = require("hardhat");
const { ethers } = require("hardhat");

async function main(){
    const accounts = await ethers.getSigners()
    const signer = accounts[0]
    const contractAddress = "0x79C604DdA2cfE62f0bF0DE879f18881609653FB6";
    const DiodePoolGoerli = await hre.ethers.getContractAt("Diode", contractAddress, signer);

    const usdc_address = '0x1643e812ae58766192cf7d2cf9567df2c37e9b7f';
    const frax_address = '0x853d955aCEf822Db058eb8505911ED77F175b99e';

    const ausdc_address = '0xBcca60bB61934080951369a648Fb03DF4F96263C';
    const ilendingpool_addressesprovider = '0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5';
    const token_abi = ['function transfer(address,uint256) external',
    'function balanceOf(address) external view returns(uint256)',
    'function approve(address,uint256) external'];

    async function getUSD(from, to, amount) {
    await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [from],
    });

    const signer = await ethers.getSigner(from);
    const usdc = new ethers.Contract(usdc_address, token_abi, signer);

    
    //const tx1 = await DiodePoolGoerli.setStrategy("0x594bA4aE95a59d64bbadAbE18EA9bb1fF8f64bE5");
    //console.log(tx1);

    const tx1 = await Di
    const tx2 = await DiodePoolGoerli.depositFunds(0.05 , );
    console.log(tx2);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });