import { network, run } from "hardhat"

async function main() {
    const orbPondImplementationAddress = process.env.ORB_POND_ADDRESS

    console.log("Orb Pond V2 Implementation Address:", orbPondImplementationAddress)

    if (network.name === "goerli" || network.name === "sepolia" || network.name === "mainnet") {
        console.log(
            `Beginning OrbPondV2 contract ${orbPondImplementationAddress} verification on ${network.name} Etherscan...`
        )
        await run(`verify:verify`, {
            address: orbPondImplementationAddress,
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
