import "@typechain/hardhat"
import "@nomicfoundation/hardhat-toolbox"

import { expect } from "chai"
import { ethers } from "hardhat"
import { BigNumber } from "ethers"
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
  let beforeDeposit: SnapshotRestorer
  let beforeWithdrawal: SnapshotRestorer

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
    // await orbUser2.closeAuction()
  })

  after(async () => {
    await testSnapshot.restore()
  })

  it("Should correctly report the foreclosure date", async function () {
    await expect(orbUser2.closeAuction()).to.not.be.reverted
    closeTimestamp = await time.latest()
    afterClose = await takeSnapshot()
    expect(await orbUser.price()).to.be.eq(ethers.utils.parseEther("1"))
    expect(await orbUser.fundsOf(user.address)).to.be.eq(ethers.utils.parseEther("0.1"))
    expect(await orbUser.foreclosureTime()).to.be.eq(closeTimestamp + year)
  })
  it("Should not allow any transfers", async function () {
    await expect(orbUser.transferFrom(user.address, user2.address, 0)).to.be.revertedWithCustomError(
      orbDeployer,
      "TransferringNotSupported"
    )
    await expect(
      orbUser["safeTransferFrom(address,address,uint256)"](user.address, user2.address, 0)
    ).to.be.revertedWithCustomError(orbDeployer, "TransferringNotSupported")
    await expect(
      orbUser["safeTransferFrom(address,address,uint256,bytes)"](
        user.address,
        user2.address,
        0,
        ethers.utils.randomBytes(32)
      )
    ).to.be.revertedWithCustomError(orbDeployer, "TransferringNotSupported")
  })
  it("Should allow the holder to change the price", async function () {
    expect(await orbUser.price()).to.be.eq(ethers.utils.parseEther("1"))
    expect(await orbUser.fundsOf(user.address)).to.be.eq(ethers.utils.parseEther("0.1"))
    expect(await orbUser.foreclosureTime()).to.be.eq(closeTimestamp + year)

    await time.setNextBlockTimestamp(closeTimestamp + year * 0.5)
    await expect(orbUser.setPrice(defaultValue.mul(2)))
      .to.emit(orbDeployer, "NewPrice")
      .withArgs(defaultValue, defaultValue.mul(2))

    expect(await orbUser.price()).to.be.eq(ethers.utils.parseEther("2"))
  })
  it("Should have a limit for maximum price", async function () {
    await expect(orbUser.setPrice(BigNumber.from(2).pow(129))).to.be.revertedWithCustomError(
      orbDeployer,
      "InvalidNewPrice"
    )
  })
  it("Should adjust foreclosure date after price adjustment", async function () {
    expect(await orbUser.foreclosureTime()).to.be.eq(closeTimestamp + year * 0.75)
  })
  it("Should report maximum foreclosure date if the price is zero", async function () {
    const beforeZeroPrice = await takeSnapshot()
    expect(await orbUser.price()).to.be.eq(ethers.utils.parseEther("2"))
    await expect(orbUser.setPrice(0)).to.emit(orbDeployer, "NewPrice").withArgs(defaultValue.mul(2), 0)
    expect(await orbUser.foreclosureTime()).to.be.eq(ethers.constants.MaxUint256)
    expect(await orbUser.price()).to.be.eq(0)
    await beforeZeroPrice.restore()
  })
  it("Should not allow anyone else to change the price", async function () {
    await expect(orbUser2.setPrice(defaultValue.mul(3))).to.revertedWithCustomError(orbDeployer, "NotHolder")
  })
  it("Should correctly report effective funds", async function () {
    await afterClose.restore()
    await time.increase(year * 0.25)

    await expect(orbUser.fundsOf(ethers.constants.AddressZero)).to.be.revertedWithCustomError(
      orbDeployer,
      "InvalidAddress"
    )

    expect(await orbUser.fundsOf(user.address)).to.be.eq(ethers.utils.parseEther("0.1"))
    const ownerFunds = await orbUser.fundsOf(deployer.address)
    const user2Funds = await orbUser.fundsOf(user2.address)
    expect(await orbUser.effectiveFundsOf(user.address)).to.be.eq(ethers.utils.parseEther("0.075"))
    expect(await orbUser.effectiveFundsOf(deployer.address)).to.be.eq(ethers.utils.parseEther("0.025").add(ownerFunds))

    await time.setNextBlockTimestamp(closeTimestamp + year * 0.5)
    await expect(orbUser2.settle()).to.emit(orbDeployer, "Settlement")
    expect(await orbUser.fundsOf(user.address)).to.be.eq(ethers.utils.parseEther("0.05"))
    expect(await orbUser.fundsOf(deployer.address)).to.be.eq(ownerFunds.add(ethers.utils.parseEther("0.05")))
    expect(await orbUser.fundsOf(user2.address)).to.be.eq(user2Funds)
    expect(await orbUser.effectiveFundsOf(user.address)).to.be.eq(ethers.utils.parseEther("0.05"))
    expect(await orbUser.effectiveFundsOf(deployer.address)).to.be.eq(ownerFunds.add(ethers.utils.parseEther("0.05")))
    expect(await orbUser.effectiveFundsOf(user2.address)).to.be.eq(user2Funds)

    expect(await orbUser.lastSettlementTime()).to.be.eq(await time.latest())
  })
  it("Should allow anyone to settle what holder owes", async function () {
    await afterClose.restore()
    const expectedForeclosureTime = closeTimestamp + year
    await time.increase(year * 0.25)

    expect(await orbUser.fundsOf(user.address)).to.be.eq(ethers.utils.parseEther("0.1"))
    expect(await orbUser.foreclosureTime()).to.be.eq(expectedForeclosureTime)
    const ownerFunds = await orbUser.fundsOf(deployer.address)

    await time.setNextBlockTimestamp(closeTimestamp + year * 0.5)
    await expect(orbUser2.settle()).to.emit(orbDeployer, "Settlement")
    expect(await orbUser.fundsOf(user.address)).to.be.eq(ethers.utils.parseEther("0.05"))
    expect(await orbUser.fundsOf(deployer.address)).to.be.eq(ownerFunds.add(ethers.utils.parseEther("0.05")))
    expect(await orbUser.foreclosureTime()).to.be.eq(expectedForeclosureTime)
  })
  it("Should allow deposits", async function () {
    beforeDeposit = await takeSnapshot()

    expect(await orbUser.fundsOf(user.address)).to.be.eq(ethers.utils.parseEther("0.05"))
    expect(await orbUser.foreclosureTime()).to.be.eq(closeTimestamp + year)

    await time.setNextBlockTimestamp(closeTimestamp + year * 0.75) // nine months
    await expect(orbUser.deposit({ value: ethers.utils.parseEther("0.05") })).to.emit(orbDeployer, "Deposit")
    expect(await orbUser.fundsOf(user.address)).to.be.eq(ethers.utils.parseEther("0.1"))
  })
  it("Should push foreclosure date after deposit", async function () {
    expect(await orbUser.foreclosureTime()).to.be.eq(closeTimestamp + year * 1.5) // 18 months

    await beforeDeposit.restore()
  })
  it("Should allow partial and full withdrawals", async function () {
    beforeWithdrawal = await takeSnapshot()

    // Full withdrawal
    await time.setNextBlockTimestamp(closeTimestamp + year * 0.75) // nine months
    await expect(orbUser.withdrawAll())
      .to.emit(orbDeployer, "Withdrawal")
      .withArgs(user.address, ethers.utils.parseEther("0.025"))
    expect(await orbUser.fundsOf(user.address)).to.be.eq(0)
    expect(await orbUser.foreclosureTime()).to.be.eq(closeTimestamp + year * 0.75) // now, nine months
    expect(await orbUser.holderSolvent()).to.be.eq(false)
    expect(await orbUser.ownerOf(69)).to.be.eq(user.address) // still holding

    await beforeWithdrawal.restore()
    await time.setNextBlockTimestamp(closeTimestamp + year * 0.75) // nine months
    await expect(orbUser.withdraw(ethers.utils.parseEther("0.0125")))
      .to.emit(orbDeployer, "Withdrawal")
      .withArgs(user.address, ethers.utils.parseEther("0.0125"))
    expect(await orbUser.fundsOf(user.address)).to.be.eq(ethers.utils.parseEther("0.0125"))
  })
  it("Should pull foreclosure date after withdrawal", async function () {
    await beforeWithdrawal.restore()
    expect(await orbUser.foreclosureTime()).to.be.eq(closeTimestamp + year)

    await time.setNextBlockTimestamp(closeTimestamp + year * 0.75) // nine months
    await expect(orbUser.withdraw(ethers.utils.parseEther("0.0125")))
      .to.emit(orbDeployer, "Withdrawal")
      .withArgs(user.address, ethers.utils.parseEther("0.0125"))
    expect(await orbUser.fundsOf(user.address)).to.be.eq(ethers.utils.parseEther("0.0125"))
    expect(await orbUser.holderSolvent()).to.be.eq(true)
    expect(await orbUser.ownerOf(69)).to.be.eq(user.address) // still holding

    expect(await orbUser.foreclosureTime()).to.be.eq(closeTimestamp + year * 0.875)
  })
}
