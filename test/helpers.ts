import { ethers } from "ethers"
import { keccak256 } from "@ethersproject/keccak256"
import { toUtf8Bytes } from "@ethersproject/strings"

export const year = 365 * 24 * 60 * 60

export const triggerData = keccak256(toUtf8Bytes("what is 42?"))

export const defaultValue = ethers.utils.parseEther("1")

export const logDate = (name: string, timestamp: number) => {
  console.log(name, new Date(timestamp * 1000))
}
