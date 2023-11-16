import { network, run } from "hardhat"

async function main() {
    const orbInvocationTipJarImplementationAddress = process.env.ORB_INVOCATION_TIP_JAR_ADDRESS

    console.log("Orb Invocation Tip Jar Address:", orbInvocationTipJarImplementationAddress)

    if (network.name === "goerli" || network.name === "sepolia" || network.name === "mainnet") {
        console.log(
            `Beginning OrbInvocationTipJar contract ${orbInvocationTipJarImplementationAddress} verification on ${network.name} Etherscan...`
        )
        await run(`verify:verify`, {
            address: orbInvocationTipJarImplementationAddress,
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
