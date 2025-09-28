const { ethers } = require("hardhat");

async function main() {
  const pyUSDCAddress = "0x637A1259C6afd7E3AdF63993cA7E58BB438aB1B1"; //

  const YTPay = await ethers.getContractFactory("YTPay");
  const ytPay = await YTPay.deploy(pyUSDCAddress);

  await ytPay.waitForDeployment();
  console.log("YTPay deployed to:", ytPay.target);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
