require("@nomicfoundation/hardhat-toolbox");
const dotenv = require("dotenv");

dotenv.config();

const path = require("path");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.28",
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },
  defaultNetwork: "hardhat",
  namedAccounts: {
    deployer: {
      default: 0,
    }
  },
  networks: {
    hardhat: {
      chainId: 1337
    },
    sepolia: {
      url: `https://eth-sepolia.g.alchemy.com/v2/${process.env.SEPOLIA_ALCHEMY_API_KEY}`,
      chainId: 11155111,
      accounts: [String(process.env.TEST_PRV_KEY)]
    },
    base: {
      url: `https://1rpc.io/base`,
      chainId: 8453,
      accounts: [String(process.env.PRV_KEY)]
    }
  },
  etherscan: {
    apiKey: {
      base: String(process.env.BASESCAN_API_KEY),
      sepolia: String(process.env.ETHERSCAN_API_KEY)
    },
    customChains: [
      {
        network: "base",
        chainId: 8453,
        urls: {
        apiURL: "https://api.basescan.org/api",
        browserURL: "https://basescan.org/"
        }
      }
    ]
  },
  resolve: {
    alias: {
      "@openzeppelin": path.resolve(__dirname, "node_modules/@openzeppelin/contracts")
    }
  },
};