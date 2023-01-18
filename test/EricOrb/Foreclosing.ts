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
  let afterFinalize: SnapshotRestorer
  let afterForeclosure: SnapshotRestorer

  let finalizeTimestamp: number

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
    await orbUser2.finalizeAuction()
    finalizeTimestamp = await time.latest()
    afterFinalize = await takeSnapshot()
  })

  after(async () => {
    await testSnapshot.restore()
  })

  it("Should allow the holder to exit by withdrawing and returning the orb", async function () {
    const balanceBeforeExit = await user.getBalance()
    expect(await orbDeployer.ownerOf(69)).to.be.eq(user.address)
    expect(await orbUser.fundsOf(user.address)).to.be.equal(ethers.utils.parseEther("0.1"))

    await time.setNextBlockTimestamp(finalizeTimestamp + year * 0.5)
    const exitTx = await orbUser.exit()
    const exitReceipt = await exitTx.wait()
    const exitGasCost = exitReceipt.gasUsed.mul(exitReceipt.effectiveGasPrice)
    await expect(exitTx).to.emit(orbDeployer, "Foreclosure").withArgs(user.address)

    expect(await orbDeployer.ownerOf(69)).to.be.eq(orbDeployer.address)
    const fundsAfterExit = await orbUser.fundsOf(user.address)
    expect(fundsAfterExit).to.be.equal(0)

    const balanceAfterExit = await user.getBalance()
    expect(balanceAfterExit).to.be.equal(balanceBeforeExit.add(ethers.utils.parseEther("0.05")).sub(exitGasCost))
  })
  it("Should not allow to deposit funds if the holder is insolvent", async function () {
    await afterFinalize.restore()
    await time.setNextBlockTimestamp(finalizeTimestamp + year + 60 * 60) // 1 year and 1 hour
    await expect(orbUser.deposit({ value: ethers.utils.parseEther("0.1") })).to.be.revertedWithCustomError(
      orbDeployer,
      "HolderInsolvent"
    )
  })
  it("Should not allow to exit if the holder is insolvent", async function () {
    await afterFinalize.restore()
    await time.setNextBlockTimestamp(finalizeTimestamp + year + 60 * 60) // 1 year and 1 hour
    await expect(orbUser.exit()).to.be.revertedWithCustomError(orbDeployer, "HolderInsolvent")
  })
  it("Should allow anyone to foreclose an insolvent holder", async function () {
    await afterFinalize.restore()
    await time.setNextBlockTimestamp(finalizeTimestamp + year + 60 * 60) // 1 year and 1 hour
    await expect(orbUser2.foreclose()).to.emit(orbDeployer, "Foreclosure").withArgs(user.address)
    expect(await orbUser.fundsOf(user.address)).to.be.eq(0)
    expect(await orbUser.ownerOf(69)).to.be.eq(orbDeployer.address)
    await expect(orbUser.price()).to.be.revertedWithCustomError(orbDeployer, "ContractHoldsOrb")
    await expect(orbUser.holderSolvent()).to.be.revertedWithCustomError(orbDeployer, "ContractHoldsOrb")
  })
  it("Should not allow to foreclose a solvent holder", async function () {
    await afterFinalize.restore()
    await time.setNextBlockTimestamp(finalizeTimestamp + year - 60 * 60) // 1 year - 1 hour
    await expect(orbUser2.foreclose()).to.be.revertedWithCustomError(orbDeployer, "HolderSolvent")
    expect(await orbUser.ownerOf(69)).to.be.eq(user.address)
    expect(await orbUser.price()).to.be.greaterThan(0)
    expect(await orbUser.holderSolvent()).to.be.true
  })
  it("Should not allow to foreclose the contract owner", async function () {
    await afterFinalize.restore()
    await expect(
      orbDeployer.purchase(defaultValue, defaultValue, { value: defaultValue.add(ethers.utils.parseEther("0.1")) })
    ).to.not.be.reverted
    await expect(orbDeployer.setPrice(ethers.utils.parseEther("100"))).to.not.be.reverted

    await time.setNextBlockTimestamp(finalizeTimestamp + year * 100) // 100 years
    await expect(orbUser.foreclose()).to.be.revertedWithCustomError(orbDeployer, "HolderSolvent")
  })
  it("Should not do anything when settling when held by contract owner", async function () {
    await expect(orbUser.settle()).to.not.emit(orbDeployer, "Settlement")
  })
  it("Should allow the contract owner to restart the auction after foreclosure", async function () {
    await afterFinalize.restore()

    await time.setNextBlockTimestamp(finalizeTimestamp + year + 60 * 60) // 1 year and 1 hour
    await expect(orbUser2.foreclose()).to.emit(orbDeployer, "Foreclosure").withArgs(user.address)
    afterForeclosure = await takeSnapshot()
    await expect(orbDeployer.startAuction()).to.emit(orbDeployer, "AuctionStarted")
    expect(await orbDeployer.auctionRunning()).to.be.true
  })
  it("Should not allow anyone else to restart the auction after foreclosure", async function () {
    await afterForeclosure.restore()
    await expect(orbUser.startAuction()).to.be.revertedWith("Ownable: caller is not the owner")
  })
}
