import { ethers, upgrades } from "hardhat"

async function main() {
    console.log("Platform Wallet Address:", process.env.PLATFORM_WALLET)
    console.log("Platform Fee as basis points:", process.env.PLATFORM_FEE)

    const OrbInvocationTipJar = await ethers.getContractFactory("OrbInvocationTipJar")
    const orbInvocationTipJar = await upgrades.deployProxy(
        OrbInvocationTipJar,
        [process.env.PLATFORM_WALLET, parseInt(process.env.PLATFORM_FEE as string)],
        {
            kind: "uups",
            initializer: "initialize",
        }
    )
    await orbInvocationTipJar.waitForDeployment()
    const orbInvocationTipJarAddress = await orbInvocationTipJar.getAddress()
    const orbInvocationTipJarImplementationAddress = await upgrades.erc1967.getImplementationAddress(
        orbInvocationTipJarAddress
    )

    console.log("Orb Invocation Tip Jar deployed to:", orbInvocationTipJarAddress)
    console.log("Orb Invocation Tip Jar Implementation deployed to:", orbInvocationTipJarImplementationAddress)
}

// We recommend this pattern to be able to use async/await everywhere and properly handle errors.
main().catch((error) => {
    console.error(error)
    process.exitCode = 1
})
