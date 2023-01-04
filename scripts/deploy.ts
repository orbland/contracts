import { ethers } from 'hardhat'

async function main() {
  const EricOrb = await ethers.getContractFactory('EricOrb')
  const ericOrb = await EricOrb.deploy()

  await ericOrb.deployed()
}

// We recommend this pattern to be able to use async/await everywhere and properly handle errors.
main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
