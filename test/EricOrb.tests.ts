import "@typechain/hardhat"
import "@nomicfoundation/hardhat-toolbox"
import { ethers } from "hardhat"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"

import { EricOrb__factory, EricOrb } from "../typechain-types/index"

import initialStateTests from "./EricOrb/InitialState"
import auctionTests from "./EricOrb/Auction"
import holdingTests from "./EricOrb/Holding"
import triggeringTests from "./EricOrb/Triggering"
import purchasingTests from "./EricOrb/Purchasing"
import foreclosingTests from "./EricOrb/Foreclosing"
import erc721Tests from "./EricOrb/ERC721"

describe("Eric's Orb", function () {
  let deployer: SignerWithAddress
  let orbDeployer: EricOrb

  before(async () => {
    ;[deployer] = await ethers.getSigners()

    const EricOrb = new EricOrb__factory(deployer)
    orbDeployer = await EricOrb.deploy()

    await orbDeployer.deployed()
  })

  describe("Initial State", initialStateTests)
  describe("Auction", auctionTests)
  describe("Holding", holdingTests)
  describe("Triggering and Responding", triggeringTests)
  describe("Purchasing", purchasingTests)
  describe("Exiting and Foreclosing", foreclosingTests)
  describe("ERC-721", erc721Tests)
})
