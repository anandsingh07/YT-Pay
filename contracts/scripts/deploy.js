const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying contract with:", deployer.address);
  console.log("Account balance:", (await deployer.provider.getBalance(deployer.address)).toString());

  const verifier = deployer.address; // for demo, deployer acts as verifier

  const ChannelTipping = await hre.ethers.getContractFactory("ChannelTipping");
  const tipping = await ChannelTipping.deploy(verifier);

  await tipping.waitForDeployment();

  console.log("ChannelTipping deployed to:", await tipping.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
