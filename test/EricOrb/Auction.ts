import "@typechain/hardhat"
import "@nomicfoundation/hardhat-toolbox"

import { expect } from "chai"
import { ethers } from "hardhat"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { takeSnapshot, SnapshotRestorer, time } from "@nomicfoundation/hardhat-network-helpers"

import { EricOrb__factory, EricOrb } from "../../typechain-types/index"
import { triggerData } from "../helpers"

export default function () {
    let deployer: SignerWithAddress
    let user: SignerWithAddress
    let user2: SignerWithAddress

    let orbDeployer: EricOrb
    let orbUser: EricOrb
    let orbUser2: EricOrb

    let testSnapshot: SnapshotRestorer
    let beforeFinalize: SnapshotRestorer

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
        expect(await orbDeployer.ownerOf(69)).to.be.eq(orbDeployer.address)

        await expect(orbUser2.finalizeAuction())
            .to.emit(orbDeployer, "AuctionFinalized")
            .withArgs(ethers.constants.AddressZero, 0)

        expect(await orbDeployer.balanceOf(orbDeployer.address)).to.be.eq(1)
        expect(await orbDeployer.ownerOf(69)).to.be.eq(orbDeployer.address)

        expect(await orbDeployer.startTime()).to.be.eq(0)
        expect(await orbDeployer.endTime()).to.be.eq(0)

        await afterStart.restore()
    })
    it("Should not allow repeated start of the auction", async function () {
        await expect(orbDeployer.startAuction()).to.be.revertedWithCustomError(orbDeployer, "AuctionRunning")
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
        await expect(orbUser.bid(ethers.utils.parseEther("0.09"))).to.be.revertedWithCustomError(
            orbDeployer,
            "InsufficientBid"
        )
    })
    it("Should block if there are not sufficient funds", async function () {
        await expect(
            orbUser.bid(ethers.utils.parseEther("0.1"), { value: ethers.utils.parseEther("0.1") })
        ).to.be.revertedWithCustomError(orbDeployer, "InsufficientFunds")
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
        await expect(orbUser.withdrawAll()).to.be.revertedWithCustomError(orbDeployer, "NotPermittedForWinningBidder")
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
    it("Should allow anyone to finalize the auction", async function () {
        await time.increase(31 * 60)

        expect(await orbUser2.auctionRunning()).to.be.eq(false)
        beforeFinalize = await takeSnapshot()
        await expect(orbUser2.finalizeAuction()).to.not.be.reverted
    })
    it("Should not allow starting the auction again until it is finalized", async function () {
        await beforeFinalize.restore()
        await expect(orbDeployer.startAuction()).to.be.revertedWithCustomError(orbDeployer, "AuctionRunning")
    })
    it("Should pay out the winning bid to the contract owner", async function () {
        await beforeFinalize.restore()
        const ownerFundsBefore = await orbDeployer.fundsOf(deployer.address)
        const winningBid = await orbDeployer.winningBid()
        await expect(orbUser2.finalizeAuction()).to.not.be.reverted
        const ownerFundsAfter = await orbDeployer.fundsOf(deployer.address)
        expect(ownerFundsBefore.add(winningBid)).to.eq(ownerFundsAfter)
    })
    it("Should transfer the orb to the winner", async function () {
        await beforeFinalize.restore()
        const winningBidder = await orbDeployer.winningBidder()
        expect(await orbDeployer.balanceOf(orbDeployer.address)).to.be.eq(1)
        expect(await orbDeployer.balanceOf(winningBidder)).to.be.eq(0)
        expect(await orbDeployer.ownerOf(69)).to.be.eq(orbDeployer.address)

        await expect(orbUser2.finalizeAuction()).to.not.be.reverted

        expect(await orbDeployer.balanceOf(orbDeployer.address)).to.be.eq(0)
        expect(await orbDeployer.balanceOf(winningBidder)).to.be.eq(1)
        expect(await orbDeployer.ownerOf(69)).to.be.eq(winningBidder)
    })
    it("Should set the price to the winning bid", async function () {
        await beforeFinalize.restore()
        const winningBid = await orbDeployer.winningBid()

        await expect(orbUser2.finalizeAuction()).to.not.be.reverted

        expect(await orbDeployer.price()).to.be.eq(winningBid)
        expect(await orbDeployer.winningBid()).to.be.eq(0)
    })
    it("Should allow the new holder to immediately trigger the orb", async function () {
        await beforeFinalize.restore()
        expect(await orbDeployer.lastTriggerTime()).to.be.eq(0)

        await expect(orbUser2.finalizeAuction()).to.not.be.reverted

        expect(await orbDeployer.lastTriggerTime()).to.be.greaterThan(0)
        await expect(orbUser.triggerWithHash(triggerData)).to.emit(orbDeployer, "Triggered")
    })
    it("Should not show the auction as running after closing", async function () {
        expect(await orbDeployer.auctionRunning()).to.be.eq(false)
        expect(await orbDeployer.startTime()).to.be.eq(0)
        expect(await orbDeployer.endTime()).to.be.eq(0)
        expect(await orbDeployer.winningBid()).to.be.eq(0)
        expect(await orbDeployer.winningBidder()).to.be.eq(ethers.constants.AddressZero)
    })
    it("Should not allow repeated closing of the auction", async function () {
        await expect(orbUser2.finalizeAuction()).to.be.revertedWithCustomError(orbDeployer, "AuctionNotStarted")
    })
}
