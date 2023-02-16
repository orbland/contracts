import "@typechain/hardhat"
import "@nomicfoundation/hardhat-toolbox"

import { expect } from "chai"
import { ethers } from "hardhat"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { takeSnapshot, SnapshotRestorer } from "@nomicfoundation/hardhat-network-helpers"

import { EricOrb__factory, EricOrb } from "../../typechain-types/index"
import { defaultValue } from "../helpers"

export default function () {
  let deployer: SignerWithAddress
  let user: SignerWithAddress
  let user2: SignerWithAddress

  let orbDeployer: EricOrb
  let orbUser: EricOrb
  let orbUser2: EricOrb

  let testSnapshot: SnapshotRestorer

  before(async () => {
    ;[deployer, user, user2] = await ethers.getSigners()

    const EricOrb = new EricOrb__factory(deployer)
    orbDeployer = await EricOrb.deploy()

    orbUser = orbDeployer.connect(user)
    orbUser2 = orbDeployer.connect(user2)

    await orbDeployer.deployed()

    testSnapshot = await takeSnapshot()
  })

  after(async () => {
    await testSnapshot.restore()
  })

  it("Should have minted the orb to the contract when deployed", async function () {
    expect(await orbDeployer.balanceOf(orbDeployer.address)).to.be.eq(1)
  })
  it("Should not show the auction as running", async function () {
    expect(await orbDeployer.auctionRunning()).to.be.eq(false)
  })
  it("Should not accept bids until auction is started", async function () {
    await expect(orbUser.bid(defaultValue)).to.be.revertedWithCustomError(orbDeployer, "AuctionNotRunning")
  })
  it("Should not allow closing the auction", async function () {
    await expect(orbUser.finalizeAuction()).to.be.revertedWithCustomError(orbDeployer, "AuctionNotStarted")
  })
  it("Should allow deposits", async function () {
    await expect(orbUser.deposit({ value: defaultValue })).to.not.be.reverted
  })
  it("Should allow partial and full withdrawals", async function () {
    const balanceBeforeWithdrawals = await user.getBalance()
    const partialWithdrawal = ethers.utils.parseEther("0.2")
    const totalExpectedWithdrawal = defaultValue

    const partialWithdrawalTx = await orbUser.withdraw(partialWithdrawal)
    const partialWithdrawalReceipt = await partialWithdrawalTx.wait()
    const gasSpentPartialWithdrawal = partialWithdrawalReceipt.gasUsed.mul(partialWithdrawalReceipt.effectiveGasPrice)
    await expect(partialWithdrawalTx).to.not.be.reverted

    const fundsAfterPartialWithdrawal = await orbUser.fundsOf(user.address)
    expect(fundsAfterPartialWithdrawal).to.be.equal(defaultValue.sub(partialWithdrawal))

    const balanceAfterPartialWithdrawal = await user.getBalance()
    expect(balanceAfterPartialWithdrawal).to.be.equal(
      balanceBeforeWithdrawals.add(partialWithdrawal).sub(gasSpentPartialWithdrawal)
    )

    const fullWithdrawalTx = await orbUser.withdrawAll()
    const fullWithdrawalReceipt = await fullWithdrawalTx.wait()
    const gasSpentFullWithdrawal = fullWithdrawalReceipt.gasUsed.mul(fullWithdrawalReceipt.effectiveGasPrice)
    await expect(fullWithdrawalTx).to.not.be.reverted

    const fundsAfterFullWithdrawal = await orbUser.fundsOf(user.address)
    expect(fundsAfterFullWithdrawal).to.be.equal(0)

    const balanceAfterFullWithdrawal = await user.getBalance()
    expect(balanceAfterFullWithdrawal).to.be.equal(
      balanceBeforeWithdrawals.add(totalExpectedWithdrawal).sub(gasSpentPartialWithdrawal).sub(gasSpentFullWithdrawal)
    )
  })
  it("Should not allow withdrawals for users with no funds", async function () {
    await expect(orbUser2.withdrawAll()).to.be.revertedWithCustomError(orbDeployer, "NoFunds")
  })
  it("Should not allow withdrawals for more than deposited", async function () {
    await expect(orbUser.deposit({ value: defaultValue }))
      .to.emit(orbDeployer, "Deposit")
      .withArgs(user.address, defaultValue)
    await expect(orbUser.withdraw(defaultValue.mul(2))).to.be.revertedWithCustomError(orbDeployer, "InsufficientFunds")
    await expect(orbUser.withdrawAll()).to.emit(orbDeployer, "Withdrawal").withArgs(user.address, defaultValue)
  })
  it("Should not allow settling", async function () {
    await expect(orbUser.settle()).to.be.revertedWithCustomError(orbDeployer, "ContractHoldsOrb")
  })
  it("Should not allow purchasing", async function () {
    await expect(orbUser.purchase(0, defaultValue)).to.be.revertedWithCustomError(orbDeployer, "ContractHoldsOrb")
  })
  it("Should return public variables as zero", async function () {
    expect(await orbDeployer.lastTriggerTime()).to.be.eq(0)
    expect(await orbDeployer.startTime()).to.be.eq(0)
    expect(await orbDeployer.endTime()).to.be.eq(0)
    expect(await orbDeployer.winningBidder()).to.be.eq(ethers.constants.AddressZero)
    expect(await orbDeployer.winningBid()).to.be.eq(0)
  })
  it("Should not have any triggers set", async function () {
    const firstTrigger = await orbDeployer.triggers(0)
    expect(firstTrigger.timestamp).to.be.eq(0)
  })
}
