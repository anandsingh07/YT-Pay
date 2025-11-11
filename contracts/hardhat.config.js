require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config(); // ✅ load .env variables

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.20", // match your contract version
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      viaIR: true, // ✅ fixes “Stack too deep” error
    },
  },
  networks: {
    sepolia: {
      url: process.env.SEPOLIA_RPC_URL, // 🔑 from your .env file
      accounts: [process.env.PRIVATE_KEY], // ⚠️ use your private key (never hardcode)
    },
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY || "", // optional (for contract verification)
  },
};
