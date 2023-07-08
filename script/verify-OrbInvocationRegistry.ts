import { network, run } from "hardhat"

async function main() {
    const orbInvocationRegistryImplementationAddress = process.env.ORB_INVOCATION_REGISTRY_ADDRESS
    console.log("Orb Invocation Registry Address:", orbInvocationRegistryImplementationAddress)

    if (network.name === "goerli" || network.name === "sepolia" || network.name === "mainnet") {
        console.log(
            `Beginning OrbInvocationRegistry contract ${orbInvocationRegistryImplementationAddress} verification on ${network.name} Etherscan...`
        )
        await run(`verify:verify`, {
            address: orbInvocationRegistryImplementationAddress,
            constructorArguments: [],
        })
        console.log(`Contract verification complete.`)
    } else {
        console.log(`Cannot verify contract on ${network.name} Etherscan.`)
    }
}

// We recommend this pattern to be able to use async/await everywhere and properly handle errors.
main().catch((error) => {
    console.error(error)
    process.exitCode = 1
})
