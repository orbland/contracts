import { HardhatUserConfig } from "hardhat/config"
import "@nomicfoundation/hardhat-toolbox"
import "@nomiclabs/hardhat-solhint"
import "hardhat-contract-sizer"
import "hardhat-gas-reporter"
import "solidity-coverage"

import * as dotenv from "dotenv"
dotenv.config()

const coinmarketcapKey: string | undefined = process.env.CMC_API_KEY

const config: HardhatUserConfig = {
    solidity: {
        version: "0.8.17",
        settings: {
            optimizer: {
                enabled: true,
                runs: 1000,
            },
        },
    },
    networks: {
        hardhat: {
            mining: {
                auto: true,
                interval: [3000, 6000],
            },
        },
        goerli: {
            url: `https://goerli.infura.io/v3/${process.env.INFURA_API_KEY}`,
            accounts: [process.env.DEPLOYER_PRIVATE_KEY as string],
        },
    },
    etherscan: {
        apiKey: process.env.ETHERSCAN_API_KEY,
    },
    gasReporter: {
        enabled: true,
        currency: "USD",
        coinmarketcap: coinmarketcapKey,
    },
}

export default config
