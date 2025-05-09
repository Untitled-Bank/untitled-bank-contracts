import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";
import * as dotenv from "dotenv";

dotenv.config();

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.29",
    settings: {
      optimizer: {
        enabled: true,
        runs: 2,
      },
      viaIR: true,
    },
  },
  paths: {
    sources: "./src",
    artifacts: "./artifacts",
  },
  networks: {
    hardhat: {},
    minato: {
      url: 'https://rpc.minato.soneium.org',
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
    soneium: {
      url: 'https://rpc.soneium.org',
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
  },
};

export default config;
