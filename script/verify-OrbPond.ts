import { network, run } from "hardhat"

async function main() {
    const orbPondImplementationAddress = process.env.ORB_POND_ADDRESS

    console.log("Orb Pond Implementation Address:", orbPondImplementationAddress)
    console.log("Orb Invocation Registry Address:", process.env.ORB_INVOCATION_REGISTRY_ADDRESS)
    console.log("Payment Splitter Implementation Address:", process.env.PAYMENT_SPLITTER_IMPLEMENTATION_ADDRESS)

    if (network.name === "goerli" || network.name === "sepolia" || network.name === "mainnet") {
        console.log(
            `Beginning OrbPond contract ${orbPondImplementationAddress} verification on ${network.name} Etherscan...`
        )
        await run(`verify:verify`, {
            address: orbPondImplementationAddress,
            constructorArguments: [
                process.env.ORB_INVOCATION_REGISTRY_ADDRESS,
                process.env.PAYMENT_SPLITTER_IMPLEMENTATION_ADDRESS,
            ],
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
