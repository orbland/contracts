import { ethers } from "hardhat"

async function main() {
    console.log("Orb Invocation Registry Address:", process.env.ORB_INVOCATION_REGISTRY_ADDRESS)
    console.log("Safe Wallet Address:", process.env.SAFE_ADDRESS)
    if (
        process.env.SAFE_ADDRESS === undefined ||
        process.env.SAFE_ADDRESS === "" ||
        process.env.ORB_INVOCATION_REGISTRY_ADDRESS === undefined ||
        process.env.ORB_INVOCATION_REGISTRY_ADDRESS === ""
    ) {
        console.log("Please set the SAFE_ADDRESS and ORB_INVOCATION_REGISTRY_ADDRESS environment variables.")
        return
    }
    const orbInvocationRegistry = await ethers.getContractAt(
        "OrbInvocationRegistry",
        process.env.ORB_INVOCATION_REGISTRY_ADDRESS
    )
    await orbInvocationRegistry.transferOwnership(process.env.SAFE_ADDRESS)
}

// We recommend this pattern to be able to use async/await everywhere and properly handle errors.
main().catch((error) => {
    console.error(error)
    process.exitCode = 1
})
