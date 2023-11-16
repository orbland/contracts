import { TransactionResponse } from "ethers"
import { ethers, upgrades } from "hardhat"

async function main() {
    const Orb = await ethers.getContractFactory("OrbV2")
    const orbDeployTx = (await upgrades.deployImplementation(Orb, {
        getTxResponse: true,
        unsafeAllow: ["delegatecall"],
    })) as TransactionResponse
    const orbTxReceipt = await orbDeployTx.wait()
    if (!orbTxReceipt) {
        throw new Error("Cannot verify tx receipt")
    }
    const orbAddress = orbTxReceipt.contractAddress
    console.log("Orb V2 implementation deployed to:", orbAddress)
}

// We recommend this pattern to be able to use async/await everywhere and properly handle errors.
main().catch((error) => {
    console.error(error)
    process.exitCode = 1
})
