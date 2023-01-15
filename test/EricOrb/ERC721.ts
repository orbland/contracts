import "@typechain/hardhat"
import "@nomicfoundation/hardhat-toolbox"

import { expect } from "chai"
import { ethers } from "hardhat"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { takeSnapshot, SnapshotRestorer } from "@nomicfoundation/hardhat-network-helpers"

import { EricOrb__factory, EricOrb } from "../../typechain-types/index"

export default function () {
  let deployer: SignerWithAddress
  let user: SignerWithAddress

  let orbDeployer: EricOrb
  let orbUser: EricOrb

  let testSnapshot: SnapshotRestorer

  before(async () => {
    ;[deployer, user] = await ethers.getSigners()

    const EricOrb = new EricOrb__factory(deployer)
    orbDeployer = await EricOrb.deploy()

    orbUser = orbDeployer.connect(user)

    await orbDeployer.deployed()

    testSnapshot = await takeSnapshot()
  })

  after(async () => {
    await testSnapshot.restore()
  })

  it("Should return a correct token URI", async function () {
    expect(await orbUser.tokenURI(69)).to.be.eq("https://static.orb.land/eric/69")
  })
}
