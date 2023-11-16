import { network, run } from "hardhat"

async function main() {
    const paymentSplitterAddress = process.env.PAYMENT_SPLITTER_ADDRESS
    console.log("PaymentSplitter Address:", paymentSplitterAddress)

    if (network.name === "goerli" || network.name === "sepolia" || network.name === "mainnet") {
        console.log(
            `Beginning PaymentSplitter contract ${paymentSplitterAddress} verification on ${network.name} Etherscan...`
        )
        await run(`verify:verify`, {
            address: paymentSplitterAddress,
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
