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
  let afterFinalize: SnapshotRestorer

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
    afterFinalize = await takeSnapshot()
  })

  after(async () => {
    await testSnapshot.restore()
  })

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
    await afterFinalize.restore()
    await expect(orbUser.trigger(triggerData, "")).to.not.be.reverted
    await time.increase((await orbDeployer.COOLDOWN()).sub(60 * 60)) // 1 hour before cooldown expires
    await expect(orbUser.trigger(triggerData, "what is 42?")).to.be.revertedWithCustomError(
      orbDeployer,
      "CooldownIncomplete"
    )
  })
  it("Should not allow anyone but the holder to trigger the orb", async function () {
    await afterFinalize.restore()
    expect(await orbUser.cooldownRemaining()).to.be.eq(0)
    await expect(orbUser2.trigger(triggerData, "")).to.be.revertedWithCustomError(orbDeployer, "NotHolder")
  })
  it("Should allow the holder to trigger the orb", async function () {
    await afterFinalize.restore()
    expect(await orbUser.cooldownRemaining()).to.be.eq(0)
    const timestampBeforeTrigger = await time.latest()
    const triggerTimestamp = timestampBeforeTrigger + 60 * 60 // 1 hour later
    await time.setNextBlockTimestamp(triggerTimestamp)
    await expect(orbUser.trigger(triggerData, "a".repeat(281))).to.be.revertedWithCustomError(
      orbDeployer,
      "CleartextTooLong"
    )
    await expect(orbUser.trigger(triggerData, ""))
      .to.emit(orbDeployer, "Triggered")
      .withArgs(user.address, 0, triggerData, triggerTimestamp)
    const firstTrigger = await orbDeployer.triggers(0)
    expect(firstTrigger.timestamp).to.be.eq(triggerTimestamp)
    expect(firstTrigger.contentHash).to.be.eq(triggerData)
    expect(await orbDeployer.triggersCount()).to.be.eq(1)

    const secondTriggerTimestamp = timestampBeforeTrigger + 7 * 24 * 60 * 60 + 2 * 60 * 60 // 1 week and 2 hours
    await time.setNextBlockTimestamp(secondTriggerTimestamp)
    await expect(orbUser.trigger(triggerData, "what is 0?")).to.be.revertedWithCustomError(
      orbDeployer,
      "CleartextHashMismatch"
    )
    await expect(orbUser.trigger(triggerData, "what is 42?"))
      .to.emit(orbDeployer, "Triggered")
      .withArgs(user.address, 1, triggerData, secondTriggerTimestamp)
    expect(await orbDeployer.triggersCount()).to.be.eq(2)
  })
  it("Should not allow providing incorrect cleartext", async function () {
    await expect(orbUser.recordTriggerCleartext(0, "a".repeat(281))).to.be.revertedWithCustomError(
      orbDeployer,
      "CleartextTooLong"
    )
    await expect(orbUser.recordTriggerCleartext(0, "what is 0?")).to.be.revertedWithCustomError(
      orbDeployer,
      "CleartextHashMismatch"
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
    await expect(orbDeployer.respond(0, triggerData)).to.be.revertedWithCustomError(orbDeployer, "ResponseExists")
  })
  it("Should not allow the contract owner to respond to a non-existing trigger", async function () {
    await expect(orbDeployer.respond(2, triggerData)).to.be.revertedWithCustomError(orbDeployer, "TriggerNotFound")
  })
  it("Should allow the holder to flag a response", async function () {
    await expect(orbUser.flagResponse(0)).to.emit(orbDeployer, "ResponseFlagged").withArgs(user.address, 0)
  })
  it("Should not allow the holder to flag a response twice", async function () {
    await expect(orbUser.flagResponse(0)).to.be.revertedWithCustomError(orbDeployer, "ResponseAlreadyFlagged")
  })
  it("Should not allow the holder to flag a non-existing response", async function () {
    await expect(orbUser.flagResponse(1)).to.be.revertedWithCustomError(orbDeployer, "ResponseNotFound")
  })
  it("Should not allow the holder to flag a response older than a week", async function () {
    await expect(orbDeployer.respond(1, triggerData)).to.emit(orbDeployer, "Responded")
    await time.increase(7 * 24 * 60 * 60 + 60 * 60) // 1 week and 1 hour
    await expect(orbUser.flagResponse(1)).to.be.revertedWithCustomError(orbDeployer, "FlaggingPeriodExpired")
  })
  it("Should allow checking if any responses are flagged", async function () {
    expect(await orbUser.flaggedResponsesCount()).to.be.eq(1)
    expect(await orbUser.responseFlagged(0)).to.be.true
    expect(await orbUser.responseFlagged(1)).to.be.false
  })
}
