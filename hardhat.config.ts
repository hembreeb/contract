import { HardhatUserConfig } from 'hardhat/config'
import '@nomicfoundation/hardhat-toolbox'

const config: HardhatUserConfig = {
  solidity: {
    compilers: [{ version: '0.8.12',
      settings: {
        optimizer: {
          enabled: true,
          runs: 2000000,
          details: {
            yul: true
          }
        }
      }}, { version: '0.7.6',
      settings: {
        optimizer: {
          enabled: true,
          runs: 2000000,
          details: {
            yul: true
          }
        }
      }}, { version: '0.4.25',
      settings: {
        optimizer: {
          enabled: true,
          runs: 2000000,
          details: {
            yul: true
          }
        }
      }}]
  },
  networks: {
    testnet: {
      url: 'https://api.hyperspace.node.glif.io/rpc/v1'
    }
  }
}

export default config
