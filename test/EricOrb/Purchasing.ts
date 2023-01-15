import "@typechain/hardhat"
import "@nomicfoundation/hardhat-toolbox"

import { expect } from "chai"
import { ethers } from "hardhat"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { takeSnapshot, SnapshotRestorer, time } from "@nomicfoundation/hardhat-network-helpers"

import { EricOrb__factory, EricOrb } from "../../typechain-types/index"
import { defaultValue, year } from "../helpers"

export default function () {
  let deployer: SignerWithAddress
  let user: SignerWithAddress
  let user2: SignerWithAddress

  let orbDeployer: EricOrb
  let orbUser: EricOrb
  let orbUser2: EricOrb

  let testSnapshot: SnapshotRestorer
  let afterClose: SnapshotRestorer

  let closeTimestamp: number

  before(async () => {
    ;[deployer, user, user2] = await ethers.getSigners()

    const EricOrb = new EricOrb__factory(deployer)
    orbDeployer = await EricOrb.deploy()

    orbUser = orbDeployer.connect(user)
    orbUser2 = orbDeployer.connect(user2)

    await orbDeployer.deployed()

    testSnapshot = await takeSnapshot()

    await orbDeployer.startAuction()
    await orbUser.bid(ethers.utils.parseEther("1"), { value: ethers.utils.parseEther("1.1") })
    await time.increase(60 * 60 * 24 + 60)
    await orbUser2.closeAuction()
    closeTimestamp = await time.latest()
    afterClose = await takeSnapshot()
  })

  after(async () => {
    await testSnapshot.restore()
  })

  it("Should block purchases with incorrect current price to prevent front-running", async function () {
    expect(await orbUser2.price()).to.be.eq(defaultValue)
    await expect(
      orbUser2.purchase(ethers.utils.parseEther("0.1"), ethers.utils.parseEther("0.5"), { value: defaultValue })
    ).to.be.revertedWithCustomError(orbDeployer, "CurrentPriceIncorrect")
  })
  it("Should block purchases with new price set to zero", async function () {
    expect(await orbUser2.price()).to.be.eq(defaultValue)
    await expect(
      orbUser2.purchase(defaultValue, 0, { value: ethers.utils.parseEther("1.2") })
    ).to.be.revertedWithCustomError(orbDeployer, "InvalidNewPrice")
  })
  it("Should block purchases without any funds for deposit", async function () {
    expect(await orbUser2.fundsOf(user2.address)).to.be.eq(0)
    await expect(
      orbUser2.purchase(defaultValue, ethers.utils.parseEther("2"), { value: defaultValue })
    ).to.be.revertedWithCustomError(orbDeployer, "InsufficientFunds")
  })
  it("Should allow anyone to purchase the orb at the set price", async function () {
    await expect(
      orbUser2.purchase(defaultValue, ethers.utils.parseEther("2"), { value: ethers.utils.parseEther("1.2") })
    )
      .to.emit(orbDeployer, "Purchase")
      .withArgs(user.address, user2.address)
    expect(await orbUser2.ownerOf(69)).to.be.eq(user2.address)
  })
  it("Should send funds to contract owner and previous holder", async function () {
    await afterClose.restore()
    expect(await orbUser2.price()).to.be.eq(defaultValue) // 1 ether
    expect(await orbUser2.ownerOf(69)).to.be.eq(user.address)
    const ownerFunds = await orbUser2.fundsOf(deployer.address)
    const holderFunds = await orbUser2.fundsOf(user.address)

    await time.setNextBlockTimestamp(closeTimestamp + year * 0.25)
    await expect(orbUser2.purchase(defaultValue, defaultValue, { value: ethers.utils.parseEther("1.1") })).to.not.be
      .reverted

    const expectedSettlement = ethers.utils.parseEther("0.025")

    expect(await orbUser2.fundsOf(deployer.address)).to.be.eq(
      ownerFunds.add(ethers.utils.parseEther("0.1").add(expectedSettlement))
    )
    expect(await orbUser2.fundsOf(user.address)).to.be.eq(
      holderFunds.add(ethers.utils.parseEther("0.9").sub(expectedSettlement))
    )
    expect(await orbUser2.fundsOf(user2.address)).to.be.eq(ethers.utils.parseEther("0.1"))
  })
  it("Should allow setting a new price when purchasing", async function () {
    await afterClose.restore()
    expect(await orbUser2.price()).to.be.eq(defaultValue) // 1 ether

    await time.setNextBlockTimestamp(closeTimestamp + year * 0.5)
    await expect(
      orbUser2.purchase(defaultValue, ethers.utils.parseEther("2"), { value: ethers.utils.parseEther("1.2") })
    )
      .to.emit(orbDeployer, "Purchase")
      .withArgs(user.address, user2.address)
    expect(await orbUser2.foreclosureTime()).to.be.eq(closeTimestamp + year * 1.5)
  })
  it("Should not allow purchasing from yourself", async function () {
    await afterClose.restore()
    await expect(
      orbUser.purchase(defaultValue, defaultValue, { value: ethers.utils.parseEther("1.1") })
    ).to.be.revertedWithCustomError(orbDeployer, "AlreadyHolder")
  })
  it("Should not allow purchasing if the holder is insolvent", async function () {
    await afterClose.restore()
    await time.setNextBlockTimestamp(closeTimestamp + year + 60 * 60) // 1 hour and 1 year
    await expect(
      orbUser2.purchase(defaultValue, defaultValue, { value: ethers.utils.parseEther("1.1") })
    ).to.be.revertedWithCustomError(orbDeployer, "HolderInsolvent")
  })
  it("Should allow the contract owner to purchase their own orb", async function () {
    await afterClose.restore()
    expect(await orbDeployer.owner()).to.be.eq(deployer.address)
    await expect(orbDeployer.purchase(defaultValue, defaultValue, { value: ethers.utils.parseEther("1.1") }))
      .to.emit(orbDeployer, "Purchase")
      .withArgs(user.address, deployer.address)
  })
  it("Should not change the cooldown time", async function () {
    await afterClose.restore()
    const lastTrigger = await orbDeployer.lastTriggerTime()
    await time.setNextBlockTimestamp(closeTimestamp + 3 * 24 * 60 * 60) // 3 days
    await expect(orbDeployer.purchase(defaultValue, defaultValue, { value: ethers.utils.parseEther("1.1") })).to.not.be
      .reverted
    expect(await orbDeployer.lastTriggerTime()).to.be.eq(lastTrigger)
  })
  it("Should report custom foreclosure date if held by the contract owner", async function () {
    expect(await orbDeployer.ownerOf(69)).to.be.eq(deployer.address)
    expect(await orbDeployer.foreclosureTime()).to.be.eq(ethers.constants.MaxUint256)
    expect(await orbDeployer.holderSolvent()).to.be.true
  })
}
