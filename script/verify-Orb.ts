import { network, run, ethers } from "hardhat"

async function main() {
    const orbImplementationAddress = process.env.ORB_IMPLEMENTATION_ADDRESS
    const orbAddress = process.env.ORB_ADDRESS
    const beneficiary = process.env.BENEFICIARY
    const orbName = process.env.ORB_NAME
    const orbSymbol = process.env.ORB_SYMBOL
    const orbTokenURI = process.env.ORB_TOKEN_URI

    console.log("Orb Implementation Address:", orbImplementationAddress)
    console.log("Orb Address:", orbAddress)
    console.log("Beneficiary:", beneficiary)
    console.log("Orb Name:", orbName)
    console.log("Orb Symbol:", orbSymbol)
    console.log("Orb Token URI:", orbTokenURI)

    if (network.name === "goerli" || network.name === "sepolia" || network.name === "mainnet") {
        console.log(`Beginning Orb contract ${orbAddress} verification on ${network.name} Etherscan...`)

        // bytes memory initializeCalldata =
        //     abi.encodeWithSelector(IOrb.initialize.selector, beneficiary, name, symbol, tokenURI);
        // ERC1967Proxy proxy = new ERC1967Proxy(versions[1], initializeCalldata);

        const iface = new ethers.Interface(["function initialize(address,string,string,string)"])
        // console.log("sighash", iface.getFunction("initialize")?.selector) // 5f1e6f6d ?

        // But also, you would often need/want to encode parameters
        const initializationCalldata = iface.encodeFunctionData("initialize", [
            beneficiary,
            orbName,
            orbSymbol,
            orbTokenURI,
        ])
        console.log("initializationCalldata", initializationCalldata)

        await run(`verify:verify`, {
            address: orbAddress,
            constructorArguments: [orbImplementationAddress, initializationCalldata],
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
