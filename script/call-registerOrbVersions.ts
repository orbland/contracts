import { TransactionResponse } from "ethers"
import { ethers, upgrades } from "hardhat"

async function main() {
    const orbPondAddress = process.env.ORB_POND_ADDRESS as string
    console.log("Orb Pond Address:", orbPondAddress)

    const orbV1ImplementationAddress = process.env.ORB_V1_IMPLEMENTATION as string
    console.log("Orb V1 implementation:", orbV1ImplementationAddress)

    const orbV2ImplementationAddress = process.env.ORB_V2_IMPLEMENTATION as string
    console.log("Orb V2 implementation:", orbV2ImplementationAddress)
    const OrbV2 = await ethers.getContractFactory("OrbV2")
    const orbV2Initializer = OrbV2.interface.encodeFunctionData("initializeV2()")
    // console.log(orbV2Initializer)

    // const OrbPondV2 = await ethers.getContractFactory("OrbPondV2")
    const orbPondV2 = await ethers.getContractAt("OrbPondV2", orbPondAddress)

    const registerV1Tx = await orbPondV2.registerVersion(1n, orbV1ImplementationAddress, "0x")
    await registerV1Tx.wait()
    console.log("Orb version 1 registered on Orb Pond:", await orbPondV2.versions(1n))

    const registerV2Tx = await orbPondV2.registerVersion(2n, orbV2ImplementationAddress, orbV2Initializer)
    await registerV2Tx.wait()
    console.log("Orb version 2 registered on Orb Pond:", await orbPondV2.versions(2n))

    const setInitialVersionTx = await orbPondV2.setOrbInitialVersion(2n)
    await setInitialVersionTx.wait()
    console.log("Orb Pond initial Orb version:", await orbPondV2.orbInitialVersion())
}

// We recommend this pattern to be able to use async/await everywhere and properly handle errors.
main().catch((error) => {
    console.error(error)
    process.exitCode = 1
})
