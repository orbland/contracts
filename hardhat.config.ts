import { HardhatUserConfig } from 'hardhat/config'
import '@nomicfoundation/hardhat-toolbox'
import '@nomiclabs/hardhat-solhint'
import 'hardhat-contract-sizer'
import 'hardhat-gas-reporter'

const coinmarketcapKey: string | undefined = process.env.CMC_API_KEY

const config: HardhatUserConfig = {
  solidity: '0.8.17',
  gasReporter: {
    enabled: true,
    currency: 'USD',
    coinmarketcap: coinmarketcapKey,
  },
}

export default config
