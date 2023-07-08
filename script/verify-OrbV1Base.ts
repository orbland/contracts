import { network, run } from "hardhat"

async function main() {
    const orbAddress = process.env.ORB_ADDRESS
    console.log("Orb Address:", orbAddress)

    if (network.name === "goerli" || network.name === "sepolia" || network.name === "mainnet") {
        console.log(`Beginning OrbV1 contract ${orbAddress} verification on ${network.name} Etherscan...`)
        await run(`verify:verify`, {
            address: orbAddress,
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
