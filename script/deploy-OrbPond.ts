import { ethers, upgrades } from "hardhat"

async function main() {
    console.log("Orb Invocation Registry Address:", process.env.ORB_INVOCATION_REGISTRY_ADDRESS)
    console.log("Payment Splitter Implementation Address:", process.env.PAYMENT_SPLITTER_IMPLEMENTATION_ADDRESS)

    const OrbPond = await ethers.getContractFactory("OrbPond")
    const orbPond = await upgrades.deployProxy(
        OrbPond,
        [process.env.ORB_INVOCATION_REGISTRY_ADDRESS, process.env.PAYMENT_SPLITTER_IMPLEMENTATION_ADDRESS],
        {
            kind: "uups",
            initializer: "initialize",
        }
    )
    await orbPond.waitForDeployment()
    const orbPondAddress = await orbPond.getAddress()
    const orbPondImplementationAddress = await upgrades.erc1967.getImplementationAddress(orbPondAddress)

    console.log("Orb Pond deployed to:", orbPondAddress)
    console.log("Orb Pond Implementation deployed to:", orbPondImplementationAddress)
}

// We recommend this pattern to be able to use async/await everywhere and properly handle errors.
main().catch((error) => {
    console.error(error)
    process.exitCode = 1
})
