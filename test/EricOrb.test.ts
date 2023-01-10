// import 'tsconfig-paths/register';
import "@typechain/hardhat"
import "@nomicfoundation/hardhat-toolbox"
import { keccak256 } from "@ethersproject/keccak256"
import { toUtf8Bytes } from "@ethersproject/strings"

// import 'hardhat-watcher';
// import '@tenderly/hardhat-tenderly';
// import '@primitivefi/hardhat-dodoc';
// import 'hardhat-tracer';
// import 'hardhat-contract-sizer';
// import '@nomiclabs/hardhat-solhint';
// import 'hardhat-deploy';
// import 'hardhat-deploy-ethers';
// import { smock } from '@defi-wonderland/smock';
// use(smock.matchers);
// import { should } from 'chai';
// should(); // if you like should syntax
// import '@nomicfoundation/hardhat-chai-matchers';
// import sinonChai from 'sinon-chai';
// use(sinonChai);

import { takeSnapshot, SnapshotRestorer, time } from "@nomicfoundation/hardhat-network-helpers"
import { expect } from "chai"
import { BigNumber } from "ethers"
import { EricOrb__factory, EricOrb } from "../typechain-types/index"
import { ethers } from "hardhat"

import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"

const revertReasons = {
  noRecipients: "Recipients array is empty",
  arraysUneven: "Recipients and amounts arrays are not of equal length",
  valueMismatch: "Value not equal to total deposits",
  noFunds: "No funds to withdraw",
  valueSendReverted: "Address: unable to send value, recipient may have reverted",
}

const logDate = (name: string, timestamp: number) => {
  console.log(name, new Date(timestamp * 1000))
}

describe("Eric's Orb", function () {
  let deployer: SignerWithAddress
  let user: SignerWithAddress
  let user2: SignerWithAddress

  let orbDeployer: EricOrb // with deployer
  let orbUser: EricOrb
  let orbUser2: EricOrb

  let defaultValue: BigNumber

  let afterClose: SnapshotRestorer
  let closeTimestamp: number
  const year = 365 * 24 * 60 * 60

  const triggerData = keccak256(toUtf8Bytes("what is 42?"))

  before(async () => {
    ;[deployer, user, user2] = await ethers.getSigners()

    const EricOrb = new EricOrb__factory(deployer)
    orbDeployer = await EricOrb.deploy()

    orbUser = orbDeployer.connect(user)
    orbUser2 = orbDeployer.connect(user2)

    defaultValue = ethers.utils.parseEther("1")
  })

  beforeEach(async () => {
    await orbDeployer.deployed()

    // snap = await takeSnapshot()
    // mine()
  })
  afterEach(async () => {
    // await snap.restore()
  })

  describe("Initial State", function () {
    it("Should have minted the orb to the contract when deployed", async function () {
      expect(await orbDeployer.balanceOf(orbDeployer.address)).to.be.eq(1)
    })
    it("Should not show the auction as running", async function () {
      expect(await orbDeployer.auctionRunning()).to.be.eq(false)
    })
    it("Should not accept bids until auction is started", async function () {
      await expect(orbUser.bid(defaultValue)).to.be.revertedWith("auction not running")
    })
    it("Should not allow closing the auction", async function () {
      await expect(orbUser.closeAuction()).to.be.revertedWith("auction was not started")
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
      await expect(orbUser2.withdrawAll()).to.be.revertedWith("no funds available")
    })
    it("Should not allow withdrawals for more than deposited", async function () {
      await expect(orbUser.deposit({ value: defaultValue }))
        .to.emit(orbDeployer, "Deposit")
        .withArgs(user.address, defaultValue)
      await expect(orbUser.withdraw(defaultValue.mul(2))).to.be.revertedWith("not enough funds")
      await expect(orbUser.withdrawAll()).to.emit(orbDeployer, "Withdrawal").withArgs(user.address, defaultValue)
    })
    it("Should not allow settling", async function () {
      await expect(orbUser.settle()).to.be.revertedWith("contract holds the orb")
    })
    it("Should not allow purchasing", async function () {
      await expect(orbUser.purchase(0, defaultValue)).to.be.revertedWith("contract holds the orb")
    })
    it("Should return public variables as zero", async function () {
      expect(await orbDeployer.price()).to.be.eq(0)
      expect(await orbDeployer.lastTriggerTime()).to.be.eq(0)
      expect(await orbDeployer.startTime()).to.be.eq(0)
      expect(await orbDeployer.endTime()).to.be.eq(0)
      expect(await orbDeployer.winningBidder()).to.be.eq(ethers.constants.AddressZero)
      expect(await orbDeployer.winningBid()).to.be.eq(0)
    })
    it("Should not return foreclosure-related information", async function () {
      await expect(orbDeployer.foreclosureTime()).to.be.revertedWith("contract holds the orb")
    })
    it("Should not have any triggers set", async function () {
      const firstTrigger = await orbDeployer.triggers(0)
      expect(firstTrigger.timestamp).to.be.eq(0)
    })
  })

  describe("Auction", function () {
    let beforeClose: SnapshotRestorer

    it("Should not allow anyone to start the auction", async function () {
      await expect(orbUser.startAuction()).to.be.revertedWith("Ownable: caller is not the owner")
    })
    it("Should allow the contract owner to start the auction", async function () {
      await expect(orbDeployer.startAuction()).to.not.be.reverted
    })
    it("Should not transfer the orb if no bids were made", async function () {
      const afterStart = await takeSnapshot()

      expect(await orbDeployer.auctionRunning()).to.be.eq(true)
      const expectedAuctionDuration = 60 * 60 * 24
      await time.increase(expectedAuctionDuration + 60)

      expect(await orbDeployer.auctionRunning()).to.be.eq(false)
      expect(await orbDeployer.winningBidder()).to.be.eq(ethers.constants.AddressZero)
      expect(await orbDeployer.winningBid()).to.be.eq(0)
      expect(await orbDeployer.balanceOf(orbDeployer.address)).to.be.eq(1)
      expect(await orbDeployer.ownerOf(0)).to.be.eq(orbDeployer.address)

      await expect(orbUser2.closeAuction())
        .to.emit(orbDeployer, "AuctionClosed")
        .withArgs(ethers.constants.AddressZero, 0)

      expect(await orbDeployer.balanceOf(orbDeployer.address)).to.be.eq(1)
      expect(await orbDeployer.ownerOf(0)).to.be.eq(orbDeployer.address)

      expect(await orbDeployer.startTime()).to.be.eq(0)
      expect(await orbDeployer.endTime()).to.be.eq(0)

      await afterStart.restore()
    })
    it("Should not allow repeated start of the auction", async function () {
      await expect(orbDeployer.startAuction()).to.be.revertedWith("auction running")
    })
    it("Should start with correct times", async function () {
      const lastBlockTimestamp = await time.latest()
      const expectedAuctionDuration = 60 * 60 * 24
      expect(await orbDeployer.startTime()).to.be.eq(lastBlockTimestamp)
      expect(await orbDeployer.endTime()).to.be.eq(lastBlockTimestamp + expectedAuctionDuration)
    })
    it("Should start with no winner or winning bid", async function () {
      expect(await orbDeployer.winningBidder()).to.be.eq(ethers.constants.AddressZero)
      expect(await orbDeployer.winningBid()).to.be.eq(0)
    })
    it("Should show the auction as running", async function () {
      expect(await orbDeployer.auctionRunning()).to.be.eq(true)
    })
    it("Should show a correct starting bid and funds required", async function () {
      const expectedMinBid = ethers.utils.parseEther("0.1")
      expect(await orbDeployer.minimumBid()).to.be.eq(expectedMinBid)
      expect(await orbDeployer.fundsRequiredToBid(expectedMinBid)).to.be.eq(ethers.utils.parseEther("0.11"))
    })
    it("Should block insufficiently large bids", async function () {
      await expect(orbUser.bid(ethers.utils.parseEther("0.09"))).to.be.revertedWith("bid not sufficient")
    })
    it("Should block if there are not sufficient funds", async function () {
      await expect(
        orbUser.bid(ethers.utils.parseEther("0.1"), { value: ethers.utils.parseEther("0.1") })
      ).to.be.revertedWith("not sufficient funds")
    })
    it("Should allow anyone to bid and record their funds", async function () {
      await expect(orbUser.bid(ethers.utils.parseEther("0.1"), { value: ethers.utils.parseEther("0.2") })).to.not.be
        .reverted
      expect(await orbUser.fundsOf(user.address)).to.be.eq(ethers.utils.parseEther("0.2"))
    })
    it("Should correctly report the current winner and winning bid", async function () {
      expect(await orbUser.winningBid()).to.be.eq(ethers.utils.parseEther("0.1"))
      expect(await orbUser.winningBidder()).to.be.eq(user.address)
    })
    it("Should allow repeat bids from the user reusing capital", async function () {
      // @todo replace all of these with fundsRequired and minimumBid
      await expect(orbUser.bid(ethers.utils.parseEther("0.2"), { value: ethers.utils.parseEther("0.02") })).to.not.be
        .reverted
      expect(await orbUser.fundsOf(user.address)).to.be.eq(ethers.utils.parseEther("0.22"))
      expect(await orbUser.winningBid()).to.be.eq(ethers.utils.parseEther("0.2"))
      expect(await orbUser.winningBidder()).to.be.eq(user.address)
    })
    it("Should allow bids from the contract owner", async function () {
      await expect(orbDeployer.bid(ethers.utils.parseEther("0.3"), { value: ethers.utils.parseEther("0.33") })).to.not
        .be.reverted
      expect(await orbUser.fundsOf(deployer.address)).to.be.eq(ethers.utils.parseEther("0.33"))
      expect(await orbUser.winningBid()).to.be.eq(ethers.utils.parseEther("0.3"))
      expect(await orbUser.winningBidder()).to.be.eq(deployer.address)
    })
    it("Should allow deposits", async function () {
      await expect(orbUser.deposit({ value: ethers.utils.parseEther("0.22") })).to.not.be.reverted
      expect(await orbUser.fundsOf(user.address)).to.be.eq(ethers.utils.parseEther("0.44"))
    })
    it("Should allow bids entirely from existing funds", async function () {
      await expect(orbUser.bid(ethers.utils.parseEther("0.4"))).to.not.be.reverted
    })
    it("Should not allow withdrawals from the winning bidder", async function () {
      expect(await orbUser.winningBidder()).to.be.eq(user.address)
      await expect(orbUser.withdrawAll()).to.be.revertedWith("not permitted for winning bidder")
    })
    it("Should allow withdrawals from anyone but the winning bidder", async function () {
      await expect(orbDeployer.withdrawAll()).to.not.be.reverted
    })
    it("Should extend the auction if a bid comes near the end", async function () {
      const lastBlockTimestamp = await time.latest()
      const auctionStartTime = (await orbDeployer.startTime()).toNumber()
      expect(lastBlockTimestamp - auctionStartTime < 60).to.be.true

      const expectedAuctionDuration = 60 * 60 * 24
      const nearlyAllDuration = expectedAuctionDuration - 60 * 15
      const initEndTime = (await orbDeployer.endTime()).toNumber()

      await time.increase(nearlyAllDuration)

      await expect(orbUser.bid(ethers.utils.parseEther("1"), { value: ethers.utils.parseEther("0.66") })).to.emit(
        orbDeployer,
        "UpdatedAuctionEnd"
      )

      const updatedEndTime = (await orbDeployer.endTime()).toNumber()
      expect(updatedEndTime > initEndTime).to.be.true
      expect(updatedEndTime > auctionStartTime + expectedAuctionDuration).to.be.true
    })
    it("Should allow anyone to close the auction", async function () {
      await time.increase(31 * 60)

      expect(await orbUser2.auctionRunning()).to.be.eq(false)
      beforeClose = await takeSnapshot()
      await expect(orbUser2.closeAuction()).to.not.be.reverted
    })
    it("Should not allow starting the auction again until it is closed", async function () {
      await beforeClose.restore()
      await expect(orbDeployer.startAuction()).to.be.revertedWith("auction already started")
    })
    it("Should pay out the winning bid to the contract owner", async function () {
      await beforeClose.restore()
      const ownerFundsBefore = await orbDeployer.fundsOf(deployer.address)
      const winningBid = await orbDeployer.winningBid()
      await expect(orbUser2.closeAuction()).to.not.be.reverted
      const ownerFundsAfter = await orbDeployer.fundsOf(deployer.address)
      expect(ownerFundsBefore.add(winningBid)).to.eq(ownerFundsAfter)
    })
    it("Should transfer the orb to the winner", async function () {
      await beforeClose.restore()
      const winningBidder = await orbDeployer.winningBidder()
      expect(await orbDeployer.balanceOf(orbDeployer.address)).to.be.eq(1)
      expect(await orbDeployer.balanceOf(winningBidder)).to.be.eq(0)
      expect(await orbDeployer.ownerOf(0)).to.be.eq(orbDeployer.address)

      await expect(orbUser2.closeAuction()).to.not.be.reverted

      expect(await orbDeployer.balanceOf(orbDeployer.address)).to.be.eq(0)
      expect(await orbDeployer.balanceOf(winningBidder)).to.be.eq(1)
      expect(await orbDeployer.ownerOf(0)).to.be.eq(winningBidder)
    })
    it("Should set the price to the winning bid", async function () {
      await beforeClose.restore()
      const winningBid = await orbDeployer.winningBid()
      expect(await orbDeployer.price()).to.be.eq(0)

      await expect(orbUser2.closeAuction()).to.not.be.reverted

      expect(await orbDeployer.price()).to.be.eq(winningBid)
      expect(await orbDeployer.winningBid()).to.be.eq(0)
    })
    it("Should allow the new holder to immediately trigger the orb", async function () {
      await beforeClose.restore()
      expect(await orbDeployer.lastTriggerTime()).to.be.eq(0)

      await expect(orbUser2.closeAuction()).to.not.be.reverted

      expect(await orbDeployer.lastTriggerTime()).to.be.greaterThan(0)
      await expect(orbUser.trigger(triggerData, "")).to.emit(orbDeployer, "Triggered")
    })
    it("Should not show the auction as running after closing", async function () {
      expect(await orbDeployer.auctionRunning()).to.be.eq(false)
      expect(await orbDeployer.startTime()).to.be.eq(0)
      expect(await orbDeployer.endTime()).to.be.eq(0)
      expect(await orbDeployer.winningBid()).to.be.eq(0)
      expect(await orbDeployer.winningBidder()).to.be.eq(ethers.constants.AddressZero)
    })
    it("Should not allow repeated closing of the auction", async function () {
      await expect(orbUser2.closeAuction()).to.be.revertedWith("contract does not hold the orb")
    })

    after(async function () {
      await beforeClose.restore()
    })
  })

  describe("Holding", function () {
    let beforeDeposit: SnapshotRestorer
    let beforeWithdrawal: SnapshotRestorer

    it("Should correctly report the foreclosure date", async function () {
      await expect(orbUser2.closeAuction()).to.not.be.reverted
      closeTimestamp = await time.latest()
      afterClose = await takeSnapshot()
      expect(await orbUser.price()).to.be.eq(ethers.utils.parseEther("1"))
      expect(await orbUser.fundsOf(user.address)).to.be.eq(ethers.utils.parseEther("0.1"))
      expect(await orbUser.foreclosureTime()).to.be.eq(closeTimestamp + year)
    })
    it("Should not allow any transfers", async function () {
      await expect(orbUser.transferFrom(user.address, user2.address, 0)).to.be.revertedWith(
        "transfering not supported, purchase required"
      )
      await expect(
        orbUser["safeTransferFrom(address,address,uint256)"](user.address, user2.address, 0)
      ).to.be.revertedWith("transfering not supported, purchase required")
      await expect(
        orbUser["safeTransferFrom(address,address,uint256,bytes)"](
          user.address,
          user2.address,
          0,
          ethers.utils.randomBytes(32)
        )
      ).to.be.revertedWith("transfering not supported, purchase required")
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
    it("Should adjust foreclosure date after price adjustment", async function () {
      expect(await orbUser.foreclosureTime()).to.be.eq(closeTimestamp + year * 0.75)
    })
    it("Should not allow anyone else to change the price", async function () {
      await expect(orbUser2.setPrice(defaultValue.mul(3))).to.revertedWith("not orb holder")
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
      expect(await orbUser.ownerOf(0)).to.be.eq(user.address) // still holding

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
      expect(await orbUser.ownerOf(0)).to.be.eq(user.address) // still holding

      expect(await orbUser.foreclosureTime()).to.be.eq(closeTimestamp + year * 0.875)
    })

    after(async function () {
      await afterClose.restore()
    })
  })

  describe("Triggering and Responding", function () {
    it("Should allow checking if orb is triggerable", async function () {
      // orb is immediately triggerable after purchase
      expect(await orbUser.cooldownRemaining()).to.be.eq(0)

      await expect(orbUser.trigger(triggerData, "what is 42?")).to.not.be.reverted
      expect(await orbUser.cooldownRemaining()).to.be.eq(await orbDeployer.COOLDOWN())
      await time.increase(await orbDeployer.COOLDOWN())
      expect(await orbUser.cooldownRemaining()).to.be.eq(0)
      await time.increase(await orbDeployer.COOLDOWN())
      expect(await orbUser.cooldownRemaining()).to.be.eq(0)
    })
    it("Should not allow orb triggering before the cooldown expires", async function () {
      await afterClose.restore()
      await expect(orbUser.trigger(triggerData, "")).to.not.be.reverted
      await time.increase((await orbDeployer.COOLDOWN()).sub(60 * 60)) // 1 hour before cooldown expires
      await expect(orbUser.trigger(triggerData, "what is 42?")).to.be.revertedWith("orb is not ready yet")
    })
    it("Should not allow anyone but the holder to trigger the orb", async function () {
      await afterClose.restore()
      expect(await orbUser.cooldownRemaining()).to.be.eq(0)
      await expect(orbUser2.trigger(triggerData, "")).to.be.revertedWith("not orb holder")
    })
    it("Should allow the holder to trigger the orb", async function () {
      await afterClose.restore()
      expect(await orbUser.cooldownRemaining()).to.be.eq(0)
      const timestampBeforeTrigger = await time.latest()
      const triggerTimestamp = timestampBeforeTrigger + 60 * 60 // 1 hour later
      await time.setNextBlockTimestamp(triggerTimestamp)
      await expect(orbUser.trigger(triggerData, "a".repeat(281))).to.be.revertedWith("cleartext is too long")
      await expect(orbUser.trigger(triggerData, ""))
        .to.emit(orbDeployer, "Triggered")
        .withArgs(user.address, 0, triggerData, triggerTimestamp)
      const firstTrigger = await orbDeployer.triggers(0)
      expect(firstTrigger.timestamp).to.be.eq(triggerTimestamp)
      expect(firstTrigger.contentHash).to.be.eq(triggerData)
      expect(await orbDeployer.triggersCount()).to.be.eq(1)

      const secondTriggerTimestamp = timestampBeforeTrigger + 7 * 24 * 60 * 60 + 2 * 60 * 60 // 1 week and 2 hours
      await time.setNextBlockTimestamp(secondTriggerTimestamp)
      await expect(orbUser.trigger(triggerData, "what is 0?")).to.be.revertedWith(
        "cleartext does not match content hash"
      )
      await expect(orbUser.trigger(triggerData, "what is 42?"))
        .to.emit(orbDeployer, "Triggered")
        .withArgs(user.address, 1, triggerData, secondTriggerTimestamp)
      expect(await orbDeployer.triggersCount()).to.be.eq(2)
    })
    it("Should not allow providing incorrect cleartext", async function () {
      await expect(orbUser.recordTriggerCleartext(0, "a".repeat(281))).to.be.revertedWith("cleartext is too long")
      await expect(orbUser.recordTriggerCleartext(0, "what is 0?")).to.be.revertedWith(
        "cleartext does not match content hash"
      )
    })
    it("Should allow providing correct cleartext", async function () {
      await expect(orbUser.recordTriggerCleartext(0, "what is 42?")).to.not.be.reverted
    })
    it("Should not allow anyone but the owner to respond", async function () {
      await expect(orbUser.respond(0, triggerData)).to.be.revertedWith("Ownable: caller is not the owner")
    })
    it("Should allow the contract owner to respond", async function () {
      const timestampBeforeResponse = await time.latest()
      const responseTimestamp = timestampBeforeResponse + 60 * 60 // 1 hour later
      await time.setNextBlockTimestamp(responseTimestamp)
      await expect(orbDeployer.respond(0, triggerData))
        .to.emit(orbDeployer, "Responded")
        .withArgs(deployer.address, 0, triggerData, responseTimestamp)
      const firstResponse = await orbDeployer.responses(0)
      expect(firstResponse.timestamp).to.be.eq(responseTimestamp)
      expect(firstResponse.contentHash).to.be.eq(triggerData)
    })
    it("Should not allow the contract owner to overwrite a previous response", async function () {
      await expect(orbDeployer.respond(0, triggerData)).to.be.revertedWith(
        "this orb trigger has already been responded"
      )
    })
    it("Should not allow the contract owner to respond to a non-existing trigger", async function () {
      await expect(orbDeployer.respond(2, triggerData)).to.be.revertedWith("this orb trigger does not exist")
    })
    it("Should allow the holder to flag a response", async function () {
      await expect(orbUser.flagResponse(0)).to.emit(orbDeployer, "ResponseFlagged").withArgs(user.address, 0)
    })
    it("Should not allow the holder to flag a response twice", async function () {
      await expect(orbUser.flagResponse(0)).to.be.revertedWith("response has already been flagged")
    })
    it("Should not allow the holder to flag a non-existing response", async function () {
      await expect(orbUser.flagResponse(1)).to.be.revertedWith("response does not exist")
    })
    it("Should not allow the holder to flag a response older than a week", async function () {
      await expect(orbDeployer.respond(1, triggerData)).to.emit(orbDeployer, "Responded")
      await time.increase(7 * 24 * 60 * 60 + 60 * 60) // 1 week and 1 hour
      await expect(orbUser.flagResponse(1)).to.be.revertedWith("response is too old to flag")
    })
    it("Should allow checking if any responses are flagged", async function () {
      expect(await orbUser.flaggedResponsesCount()).to.be.eq(1)
      expect(await orbUser.responseFlagged(0)).to.be.true
      expect(await orbUser.responseFlagged(1)).to.be.false
    })

    after(async function () {
      await afterClose.restore()
    })
  })

  describe("Purchasing", function () {
    it("Should block purchases with incorrect current price to prevent front-running", async function () {
      expect(await orbUser2.price()).to.be.eq(defaultValue)
      await expect(
        orbUser2.purchase(ethers.utils.parseEther("0.1"), ethers.utils.parseEther("0.5"), { value: defaultValue })
      ).to.be.revertedWith("current price incorrect")
    })
    it("Should block purchases without any funds for deposit", async function () {
      expect(await orbUser2.fundsOf(user2.address)).to.be.eq(0)
      await expect(
        orbUser2.purchase(defaultValue, ethers.utils.parseEther("2"), { value: defaultValue })
      ).to.be.revertedWith("not enough funds")
    })
    it("Should allow anyone to purchase the orb at the set price", async function () {
      await expect(
        orbUser2.purchase(defaultValue, ethers.utils.parseEther("2"), { value: ethers.utils.parseEther("1.2") })
      )
        .to.emit(orbDeployer, "Purchase")
        .withArgs(user.address, user2.address)
      expect(await orbUser2.ownerOf(0)).to.be.eq(user2.address)
    })
    it("Should send funds to contract owner and previous holder", async function () {
      await afterClose.restore()
      expect(await orbUser2.price()).to.be.eq(defaultValue) // 1 ether
      expect(await orbUser2.ownerOf(0)).to.be.eq(user.address)
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
      ).to.be.revertedWith("you already own the orb")
    })
    it("Should not allow purchasing if the holder is insolvent", async function () {
      await afterClose.restore()
      await time.setNextBlockTimestamp(closeTimestamp + year + 60 * 60) // 1 hour and 1 year
      await expect(
        orbUser2.purchase(defaultValue, defaultValue, { value: ethers.utils.parseEther("1.1") })
      ).to.be.revertedWith("holder insolvent")
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
      await expect(orbDeployer.purchase(defaultValue, defaultValue, { value: ethers.utils.parseEther("1.1") })).to.not
        .be.reverted
      expect(await orbDeployer.lastTriggerTime()).to.be.eq(lastTrigger)
    })
    it("Should report custom foreclosure date if held by the contract owner", async function () {
      expect(await orbDeployer.ownerOf(0)).to.be.eq(deployer.address)
      expect(await orbDeployer.foreclosureTime()).to.be.eq(0)
      expect(await orbDeployer.holderSolvent()).to.be.true
    })

    after(async function () {
      await afterClose.restore()
    })
  })

  describe("Exiting and Foreclosing", function () {
    let afterForeclosure: SnapshotRestorer

    it("Should allow the holder to exit by withdrawing and returning the orb", async function () {
      const balanceBeforeExit = await user.getBalance()
      expect(await orbDeployer.ownerOf(0)).to.be.eq(user.address)
      expect(await orbUser.fundsOf(user.address)).to.be.equal(ethers.utils.parseEther("0.1"))

      await time.setNextBlockTimestamp(closeTimestamp + year * 0.5)
      const exitTx = await orbUser.exit()
      const exitReceipt = await exitTx.wait()
      const exitGasCost = exitReceipt.gasUsed.mul(exitReceipt.effectiveGasPrice)
      await expect(exitTx).to.emit(orbDeployer, "Foreclosure").withArgs(user.address)

      expect(await orbDeployer.ownerOf(0)).to.be.eq(orbDeployer.address)
      const fundsAfterExit = await orbUser.fundsOf(user.address)
      expect(fundsAfterExit).to.be.equal(0)

      const balanceAfterExit = await user.getBalance()
      expect(balanceAfterExit).to.be.equal(balanceBeforeExit.add(ethers.utils.parseEther("0.05")).sub(exitGasCost))
    })
    it("Should not allow to deposit funds if the holder is insolvent", async function () {
      await afterClose.restore()
      await time.setNextBlockTimestamp(closeTimestamp + year + 60 * 60) // 1 year and 1 hour
      await expect(orbUser.deposit({ value: ethers.utils.parseEther("0.1") })).to.be.revertedWith(
        "deposits allowed only during solvency"
      )
    })
    it("Should not allow to exit if the holder is insolvent", async function () {
      await afterClose.restore()
      await time.setNextBlockTimestamp(closeTimestamp + year + 60 * 60) // 1 year and 1 hour
      await expect(orbUser.exit()).to.be.revertedWith("holder insolvent")
    })
    it("Should allow anyone to foreclose an insolvent holder", async function () {
      await afterClose.restore()
      await time.setNextBlockTimestamp(closeTimestamp + year + 60 * 60) // 1 year and 1 hour
      await expect(orbUser2.foreclose()).to.emit(orbDeployer, "Foreclosure").withArgs(user.address)
      expect(await orbUser.fundsOf(user.address)).to.be.eq(0)
      expect(await orbUser.ownerOf(0)).to.be.eq(orbDeployer.address)
      expect(await orbUser.price()).to.be.eq(0)
      await expect(orbUser.holderSolvent()).to.be.revertedWith("contract holds the orb")
    })
    it("Should not allow to foreclose a solvent holder", async function () {
      await afterClose.restore()
      await time.setNextBlockTimestamp(closeTimestamp + year - 60 * 60) // 1 year - 1 hour
      await expect(orbUser2.foreclose()).to.be.revertedWith("holder solvent")
      expect(await orbUser.ownerOf(0)).to.be.eq(user.address)
      expect(await orbUser.price()).to.be.greaterThan(0)
      expect(await orbUser.holderSolvent()).to.be.true
    })
    it("Should not allow to foreclose the contract owner", async function () {
      await afterClose.restore()
      await expect(
        orbDeployer.purchase(defaultValue, defaultValue, { value: defaultValue.add(ethers.utils.parseEther("0.1")) })
      ).to.not.be.reverted
      await expect(orbDeployer.setPrice(ethers.utils.parseEther("100"))).to.not.be.reverted

      await time.setNextBlockTimestamp(closeTimestamp + year * 100) // 100 years
      await expect(orbUser.foreclose()).to.be.revertedWith("holder solvent")
    })
    it("Should not do anything when settling when held by contract owner", async function () {
      await expect(orbUser.settle()).to.not.emit(orbDeployer, "Settlement")
    })
    it("Should allow the contract owner to restart the auction after foreclosure", async function () {
      await afterClose.restore()

      await time.setNextBlockTimestamp(closeTimestamp + year + 60 * 60) // 1 year and 1 hour
      await expect(orbUser2.foreclose()).to.emit(orbDeployer, "Foreclosure").withArgs(user.address)
      afterForeclosure = await takeSnapshot()
      await expect(orbDeployer.startAuction()).to.emit(orbDeployer, "AuctionStarted")
      expect(await orbDeployer.auctionRunning()).to.be.true
    })
    it("Should not allow anyone else to restart the auction after foreclosure", async function () {
      await afterForeclosure.restore()
      await expect(orbUser.startAuction()).to.be.revertedWith("Ownable: caller is not the owner")
    })
  })

  describe("ERC-721", function () {
    it("Should return a correct token URI", async function () {
      expect(await orbUser.tokenURI(0)).to.be.eq("https://static.orb.land/eric/0")
    })
  })
})
