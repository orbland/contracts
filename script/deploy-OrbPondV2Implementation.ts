import { TransactionResponse } from "ethers"
import { ethers, upgrades } from "hardhat"

async function main() {
    const OrbPondV2 = await ethers.getContractFactory("OrbPondV2")

    const orbPondDeployTx = (await upgrades.deployImplementation(OrbPondV2, {
        getTxResponse: true,
    })) as TransactionResponse
    const orbPondTxReceipt = await orbPondDeployTx.wait()
    if (!orbPondTxReceipt) {
        throw new Error("Cannot verify tx receipt")
    }
    const orbPondV2Implementation = orbPondTxReceipt.contractAddress as string
    console.log("OrbPondV2 implementation deployed to:", orbPondV2Implementation)

    const data = OrbPondV2.interface.encodeFunctionData("initializeV2(uint256)", [1])
    console.log(`call: upgradeToAndCall(${orbPondV2Implementation}, ${data})`)
}

// We recommend this pattern to be able to use async/await everywhere and properly handle errors.
main().catch((error) => {
    console.error(error)
    process.exitCode = 1
})
