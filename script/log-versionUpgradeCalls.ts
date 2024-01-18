import { ethers } from "hardhat"

async function main() {
    const OrbV2 = await ethers.getContractFactory("OrbV2")
    const orbV2Initializer = OrbV2.interface.encodeFunctionData("initializeV2()")
    console.log(orbV2Initializer)

    // const registerV1Tx = await orbPondV2.registerVersion(1n, orbV1ImplementationAddress, "0x")
    // const registerV2Tx = await orbPondV2.registerVersion(2n, orbV2ImplementationAddress, orbV2Initializer)
    // const setInitialVersionTx = await orbPondV2.setOrbInitialVersion(2n)
}

// We recommend this pattern to be able to use async/await everywhere and properly handle errors.
main().catch((error) => {
    console.error(error)
    process.exitCode = 1
})
