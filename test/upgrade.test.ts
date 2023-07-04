import { PaymentSplitter } from "./../typechain-types/src/CustomPaymentSplitter.sol/PaymentSplitter"
import { expect } from "chai"
import { ethers, upgrades } from "hardhat"

describe("Orb Pond Upgrade", function () {
    it("Should deploy and upgrade", async function () {
        const [owner, registry] = await ethers.getSigners()

        const paymentSplitterImplementation = await ethers.deployContract(
            "src/CustomPaymentSplitter.sol:PaymentSplitter"
        )
        const paymentSplitterImplementationAddress = await paymentSplitterImplementation.getAddress()

        const OrbPond = await ethers.getContractFactory("OrbPond")
        const orbPond = await upgrades.deployProxy(OrbPond, [registry.address, paymentSplitterImplementationAddress], {
            kind: "uups",
            initializer: "initialize",
        })
        await orbPond.waitForDeployment()
        const orbPondAddress = await orbPond.getAddress()
        // console.log("Pond address:", orbPondAddress)

        expect(await orbPond.registry()).to.equal(registry.address)
        expect(await orbPond.version()).to.equal(1n)
        expect(await orbPond.owner()).to.equal(owner.address)

        const OrbPondV2 = await ethers.getContractFactory("OrbPondV2")
        const orbPondUpgraded = await upgrades.upgradeProxy(orbPondAddress, OrbPondV2, {
            kind: "uups",
        })
        // console.log("Orb Pond upgraded")
        await orbPondUpgraded.waitForDeployment()

        const orbAddressUpgraded = await orbPondUpgraded.getAddress()
        // console.log("Upgraded Pond address:", orbAddressUpgraded)
        expect(orbAddressUpgraded).to.equal(orbPondAddress)
        expect(await orbPond.version()).to.equal(2n)
    })
})

describe("Orb Registry Upgrade", function () {
    it("Should deploy and upgrade", async function () {
        const [owner] = await ethers.getSigners()
        const OrbInvocationRegistry = await ethers.getContractFactory("OrbInvocationRegistry")
        const orbInvocationRegistry = await upgrades.deployProxy(OrbInvocationRegistry, {
            kind: "uups",
            initializer: "initialize",
        })
        await orbInvocationRegistry.waitForDeployment()
        const orbInvocationRegistryAddress = await orbInvocationRegistry.getAddress()
        // console.log("InvocationRegistry address:", orbInvocationRegistryAddress)

        expect(await orbInvocationRegistry.owner()).to.equal(owner.address)
        expect(await orbInvocationRegistry.version()).to.equal(1n)

        const OrbInvocationRegistryV2 = await ethers.getContractFactory("OrbInvocationRegistryV2")
        const orbInvocationRegistryUpgraded = await upgrades.upgradeProxy(
            orbInvocationRegistryAddress,
            OrbInvocationRegistryV2,
            {
                kind: "uups",
            }
        )
        // console.log("Orb InvocationRegistry upgraded")
        await orbInvocationRegistryUpgraded.waitForDeployment()

        const orbInvocationRegistryAddressUpgraded = await orbInvocationRegistryUpgraded.getAddress()
        // console.log("Upgraded InvocationRegistry address:", orbInvocationRegistryAddressUpgraded)
        expect(orbInvocationRegistryAddressUpgraded).to.equal(orbInvocationRegistryAddress)
        expect(await orbInvocationRegistry.version()).to.equal(2n)
    })
})

describe("Orb Upgrade", function () {
    it("Should be deploy directly", async function () {
        const [admin, creator, keeper, beneficiary] = await ethers.getSigners()

        const Orb = await ethers.getContractFactory("Orb")
        const orb = await upgrades.deployProxy(Orb, [beneficiary.address, "Orb", "ORB", "https://example.com/"], {
            kind: "uups",
            initializer: "initialize",
            unsafeAllow: ["delegatecall", "missing-public-upgradeto"],
        })
        await orb.waitForDeployment()
        const orbAsCreator = orb.connect(creator) as typeof orb
        const orbAsKeeper = orb.connect(keeper) as typeof orb
        // const orbAddress = await orb.getAddress()
        // console.log("Orb address:", orbAddress)

        expect(await orb.name()).to.equal("Orb")
        expect(await orb.symbol()).to.equal("ORB")
        expect(await orb.tokenURI(1)).to.equal("https://example.com/")

        expect(await orb.beneficiary()).to.equal(beneficiary.address)
        expect(await orb.owner()).to.equal(admin.address)
        expect(await orb.version()).to.equal(1n)

        await orb.transferOwnership(creator.address)
        await orbAsCreator.listWithPrice(ethers.parseEther("1"))
        await orbAsKeeper.purchase(ethers.parseEther("2"), ethers.parseEther("1"), 1000n, 1000n, 604800n, 280n, {
            value: ethers.parseEther("1"),
        })
        expect(await orb.keeper()).to.equal(keeper.address)
        // await orb.requestUpgrade(orb.address)
    })

    it("Should deploy from Pond and upgrade", async function () {
        const [admin, creator, keeper, registry, beneficiary1, beneficiary2] = await ethers.getSigners()

        const paymentSplitterImplementation = await ethers.deployContract(
            "src/CustomPaymentSplitter.sol:PaymentSplitter"
        )
        const paymentSplitterImplementationAddress = await paymentSplitterImplementation.getAddress()

        const OrbPond = await ethers.getContractFactory("OrbPond")
        const orbPond = await upgrades.deployProxy(OrbPond, [registry.address, paymentSplitterImplementationAddress], {
            kind: "uups",
            initializer: "initialize",
        })
        await orbPond.waitForDeployment()
        const orbPondAddress = await orbPond.getAddress()
        // console.log("Pond address:", orbPondAddress)

        // const Orb = await ethers.getContractFactory("Orb")
        const orbImplementation = await ethers.deployContract("Orb")

        expect(await orbPond.registry()).to.equal(registry.address)
        expect(await orbPond.version()).to.equal(1n)
        expect(await orbPond.owner()).to.equal(admin.address)

        await orbPond.registerVersion(
            1,
            orbImplementation.getAddress(),
            ethers.AbiCoder.defaultAbiCoder().encode(["string"], ["Orb"])
        )

        await orbPond.createOrb([beneficiary1, beneficiary2], [95, 5], "Orb", "ORB", "https://example.com/")
        const firstOrbAddress = await orbPond.orbs(0)
        const orb = await ethers.getContractAt("Orb", firstOrbAddress)
        expect(await orb.name()).to.equal("Orb")
        expect(await orb.symbol()).to.equal("ORB")
        expect(await orb.tokenURI(1)).to.equal("https://example.com/")
        expect(await orb.owner()).to.equal(admin.address)
        expect(await orb.version()).to.equal(1n)

        const beneficiary = await ethers.getContractAt(
            "src/CustomPaymentSplitter.sol:PaymentSplitter",
            await orb.beneficiary()
        )
        expect(await beneficiary.totalShares()).to.equal(100)
        expect(await beneficiary.payee(0)).to.equal(beneficiary1.address)
        expect(await beneficiary.payee(1)).to.equal(beneficiary2.address)
        expect(await beneficiary.shares(beneficiary1.address)).to.equal(95n)
        expect(await beneficiary.shares(beneficiary2.address)).to.equal(5n)

        await orb.transferOwnership(creator.address)
        const orbAsCreator = orb.connect(creator) as typeof orb
        const orbAsKeeper = orb.connect(keeper) as typeof orb
        // const orbAddress = await orb.getAddress()
        // console.log("Orb address:", orbAddress)

        await orbAsCreator.listWithPrice(ethers.parseEther("1"))
        await orbAsKeeper.purchase(ethers.parseEther("2"), ethers.parseEther("1"), 1000n, 1000n, 604800n, 280n, {
            value: ethers.parseEther("2"),
        })
        expect(await orb.keeper()).to.equal(keeper.address)

        const orbV2Implementation = await ethers.deployContract("OrbV2")
        const orbV2ImplementationAddress = await orbV2Implementation.getAddress()
        await orbPond.registerVersion(
            2,
            orbV2ImplementationAddress,
            orbV2Implementation.interface.encodeFunctionData("initializeV2", ["Whorb", "WHORB"])
        )

        await orbAsCreator.requestUpgrade(orbV2Implementation.getAddress())
        expect(await orb.requestedUpgradeImplementation()).to.equal(orbV2ImplementationAddress)

        await orbAsKeeper.upgradeToNextVersion()
        expect(await orb.name()).to.equal("Whorb")
        expect(await orb.symbol()).to.equal("WHORB")
        expect(await orb.version()).to.equal(2n)
    })
})
