import { ethers, network, run } from "hardhat"

async function main() {
  console.log(network.name)
  if (network.name === "localhost") {
    console.log("localhost!")
    const EricOrb = await ethers.getContractFactory("EricOrbDev")
    const ericOrb = await EricOrb.deploy()

    await ericOrb.deployed()
  } else {
    const EricOrb = await ethers.getContractFactory("EricOrb")
    const ericOrb = await EricOrb.deploy()

    await ericOrb.deployed()

    if (network.name === "goerli") {
      const WAIT_BLOCK_CONFIRMATIONS = 6
      await ericOrb.deployTransaction.wait(WAIT_BLOCK_CONFIRMATIONS)

      console.log(`Contract deployed to ${ericOrb.address} on ${network.name}`)

      console.log(`Verifying contract on Etherscan...`)

      await run(`verify:verify`, {
        address: ericOrb.address,
        constructorArguments: [],
      })
    }
  }
}

// We recommend this pattern to be able to use async/await everywhere and properly handle errors.
main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
