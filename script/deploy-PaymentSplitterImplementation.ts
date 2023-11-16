import { TransactionResponse } from "ethers"
import { ethers, upgrades } from "hardhat"

async function main() {
    const PaymentSplitter = await ethers.getContractFactory("src/CustomPaymentSplitter.sol:PaymentSplitter")
    const paymentSplitterDeployTx = (await upgrades.deployImplementation(PaymentSplitter, {
        getTxResponse: true,
    })) as TransactionResponse
    const paymentSplitterTxReceipt = await paymentSplitterDeployTx.wait()
    if (!paymentSplitterTxReceipt) {
        throw new Error("Cannot verify tx receipt")
    }
    const paymentSplitterAddress = paymentSplitterTxReceipt.contractAddress
    console.log("Payment Splitter implementation deployed to:", paymentSplitterAddress)
}

// We recommend this pattern to be able to use async/await everywhere and properly handle errors.
main().catch((error) => {
    console.error(error)
    process.exitCode = 1
})
