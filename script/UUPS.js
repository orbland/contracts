import { ethers, upgrades } from "hardhat";

async function main() {
    const UupsProxyPatternV1 = await ethers.getContractFactory("UupsProxyPatternV1");
    const uupsProxyPatternV1 = await upgrades.deployProxy(UupsProxyPatternV1, [], { kind: 'uups', unsafeAllow: ['constructor'] });
    await uupsProxyPatternV1.deployed();
    console.log(`UUPS Proxy Pattern V1 is deployed to proxy address: ${uupsProxyPatternV1.address}`);

    let versionAwareContractName = await uupsProxyPatternV1.getContractNameWithVersion();
    console.log(`UUPS Pattern and Version: ${versionAwareContractName}`);

    const UupsProxyPatternV2 = await ethers.getContractFactory("UupsProxyPatternV2");
    const upgraded = await upgrades.upgradeProxy(uupsProxyPatternV1.address, UupsProxyPatternV2, { kind: 'uups', unsafeAllow: ['constructor'], call: 'initialize' });
    console.log(`UUPS Proxy Pattern V2 is upgraded in proxy address: ${upgraded.address}`);

    versionAwareContractName = await upgraded.getContractNameWithVersion();
    console.log(`UUPS Pattern and Version: ${versionAwareContractName}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
