import { ethers, upgrades } from "hardhat"

async function main() {
    const OrbInvocationRegistry = await ethers.getContractFactory("OrbInvocationRegistry")
    const orbInvocationRegistry = await upgrades.deployProxy(OrbInvocationRegistry, {
        kind: "uups",
        initializer: "initialize",
    })
    await orbInvocationRegistry.waitForDeployment()
    const orbInvocationRegistryAddress = await orbInvocationRegistry.getAddress()
    const orbInvocationRegistryImplementationAddress = await upgrades.erc1967.getImplementationAddress(
        orbInvocationRegistryAddress
    )

    console.log("Orb Invocation Registry deployed to:", orbInvocationRegistryAddress)
    console.log("Orb Invocation Registry Implementation deployed to:", orbInvocationRegistryImplementationAddress)
}

// We recommend this pattern to be able to use async/await everywhere and properly handle errors.
main().catch((error) => {
    console.error(error)
    process.exitCode = 1
})
