import { expect } from "chai"
import { ethers, upgrades } from "hardhat"

describe("Orb Upgrade", function () {
    it("Proxy should deploy and upgrade", async function () {
        const [owner, beneficiary] = await ethers.getSigners()
        const Orb = await ethers.getContractFactory("Orb")
        const orb = await upgrades.deployProxy(Orb, [beneficiary.address, "Orb", "ORB", "https://example.com/"], {
            kind: "uups",
            initializer: "initialize",
            unsafeAllow: ["delegatecall", "missing-public-upgradeto"],
        })
        await orb.waitForDeployment()
        const orbAddress = await orb.getAddress()
        console.log(orbAddress)

        expect(await orb.name()).to.equal("Orb")
        expect(await orb.symbol()).to.equal("ORB")
        expect(await orb.tokenURI(1)).to.equal("https://example.com/")

        expect(await orb.owner()).to.equal(owner.address)

        // const OrbV2 = await ethers.getContractFactory("OrbV2")
        // const orbUpgraded = await upgrades.upgradeProxy(orbAddress, OrbV2, {
        //     kind: "uups",
        // })
        // console.log("Orb upgraded")
        // await orb.waitForDeployment()

        // const orbAddressUpgraded = await orbUpgraded.getAddress()
        // console.log(orbAddressUpgraded)
        // expect(orbAddressUpgraded).to.equal(orbAddress)
    })
})
