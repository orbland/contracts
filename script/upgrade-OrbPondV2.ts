import { TransactionResponse } from "ethers"
import { ethers, upgrades } from "hardhat"

async function main() {
    const orbPondAddress = process.env.ORB_POND_ADDRESS as string

    console.log("Orb Pond Address:", orbPondAddress)

    const OrbPondV2 = await ethers.getContractFactory("OrbPondV2")
    // console.log(OrbPondV2)

    const orbPondDeployTx = (await upgrades.deployImplementation(OrbPondV2, {
        getTxResponse: true,
    })) as TransactionResponse
    const orbPondTxReceipt = await orbPondDeployTx.wait()
    if (!orbPondTxReceipt) {
        throw new Error("Cannot verify tx receipt")
    }
    const orbPondV2Implementation = orbPondTxReceipt.contractAddress as string
    // console.log("OrbPondV2 implementation deployed to:", orbPondV2Implementation)

    const data = OrbPondV2.interface.encodeFunctionData("initializeV2(uint256)", [1])
    // console.log(data)

    const orbPond = await ethers.getContractAt("OrbPond", orbPondAddress)
    const upgradeTx = await orbPond.upgradeToAndCall(orbPondV2Implementation, data)
    // console.log(upgradeTx)
    await upgradeTx.wait()
    // console.log(receipt)

    // const orbPondUpgradedV2 = await upgrades.upgradeProxy(orbPondAddress, OrbPondV2, {
    //     kind: "uups",
    //     call: {
    //         fn: "initializeV2(uint256)",
    //         args: [1n], // initial version 1
    //     },
    //     // redeployImplementation: "always",
    //     // unsafeAllow: ["constructor"],
    // })
    // // console.log("Orb Pond upgraded")
    // // console.log(orbPondUpgradedV2.deploymentTransaction())
    // // console.log(orbPondUpgradedV2)

    // await orbPondUpgradedV2.waitForDeployment()
    // const orbPond = await ethers.getContractAt("OrbPondV2", orbPondAddress)

    // try {
    //     const upgradeTx = await orbPond.initializeV2(1)
    //     await upgradeTx.wait()
    // } catch (error) {
    //     console.log("error, expected")
    // }

    const orbPondImplementationAddress = await upgrades.erc1967.getImplementationAddress(orbPondAddress)
    console.log("Orb Pond V2 Implementation deployed to:", orbPondImplementationAddress)
    console.log("Orb Pond upgraded to V2:", await orbPond.getAddress())

    // const orbPondV2 = await ethers.getContractAt("OrbPondV2", orbPondAddress)
    // console.log("version", await orbPondV2.version())
    // console.log("orb init version", await orbPondV2.orbInitialVersion())
}

// We recommend this pattern to be able to use async/await everywhere and properly handle errors.
main().catch((error) => {
    console.error(error)
    process.exitCode = 1
})
