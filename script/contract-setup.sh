npx hardhat run script/deploy-PaymentSplitterImplementation.ts --network anvil
# Payment Splitter implementation deployed to: 0x5FbDB2315678afecb367f032d93F642f64180aa3

npx hardhat run script/deploy-OrbInvocationRegistry.ts --network anvil
# Orb Invocation Registry deployed to: 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0
# Orb Invocation Registry Implementation deployed to: 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512

ORB_INVOCATION_REGISTRY_ADDRESS=0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0 \
PAYMENT_SPLITTER_IMPLEMENTATION_ADDRESS=0x5FbDB2315678afecb367f032d93F642f64180aa3 \
npx hardhat run script/deploy-OrbPond.ts --network anvil
# Orb Pond deployed to: 0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9
# Orb Pond Implementation deployed to: 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9

ORB_POND_ADDRESS=0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9 \
npx hardhat run script/upgrade-OrbPondV2.ts --network anvil
# Orb Pond V2 Implementation deployed to: 0x5FC8d32690cc91D4c39d9d3abcBD16989F875707
# Orb Pond upgraded to V2: 0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9

npx hardhat run script/deploy-OrbImplementation.ts --network anvil
# Orb V1 implementation deployed to: 0xa513E6E4b8f2a923D98304ec87F64353C4D5C853

npx hardhat run script/deploy-OrbV2Implementation.ts --network anvil
# Orb V2 implementation deployed to: 0x2279B7A0a67DB372996a5FaB50D91eAA73d2eBe6

ORB_POND_ADDRESS=0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9 \
ORB_V1_IMPLEMENTATION=0xa513E6E4b8f2a923D98304ec87F64353C4D5C853 \
ORB_V2_IMPLEMENTATION=0x2279B7A0a67DB372996a5FaB50D91eAA73d2eBe6 \
npx hardhat run script/call-registerOrbVersions.ts --network anvil

PLATFORM_WALLET=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
PLATFORM_FEE=500 \
npx hardhat run script/deploy-OrbInvocationTipJar.ts --network anvil
# Orb Invocation Tip Jar deployed to: 0x0DCd1Bf9A1b36cE34237eEaFef220932846BCD82
# Orb Invocation Tip Jar Implementation deployed to: 0xA51c1fc2f0D1a1b8494Ed1FE312d7C3a78Ed91C0

# Contract Verifications

PAYMENT_SPLITTER_ADDRESS=0x5FbDB2315678afecb367f032d93F642f64180aa3 \
npx hardhat run script/verify-PaymentSplitterImplementation.ts --network anvil

ORB_INVOCATION_REGISTRY_ADDRESS=0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512 \
npx hardhat run script/verify-OrbInvocationRegistryImplementation.ts --network anvil

ORB_POND_ADDRESS=0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9 \
npx hardhat run script/verify-OrbPondImplementation.ts --network anvil

ORB_POND_ADDRESS=0x5FC8d32690cc91D4c39d9d3abcBD16989F875707 \
npx hardhat run script/verify-OrbPondV2Implementation.ts --network anvil

ORB_ADDRESS=0xa513E6E4b8f2a923D98304ec87F64353C4D5C853 \
npx hardhat run script/verify-OrbImplementation.ts --network anvil

ORB_ADDRESS=0x2279B7A0a67DB372996a5FaB50D91eAA73d2eBe6 \
npx hardhat run script/verify-OrbV2Implementation.ts --network anvil

ORB_INVOCATION_TIP_JAR_ADDRESS=0xA51c1fc2f0D1a1b8494Ed1FE312d7C3a78Ed91C0 \
npx hardhat run script/verify-OrbInvocationTipJarImplementation.ts --network anvil

# Orb Proxy Verification

# ORB_IMPLEMENTATION_ADDRESS=0x10b0e79D892Be4345F800501378F1eD144824Ae1 \
# ORB_ADDRESS=0x7aAd4004576482a952B8382f0DcF71D64CF77f25 \
# BENEFICIARY=0xAE684f43F12758ED4eE6016Ae8cbfb61416B618a \
# ORB_NAME="TestOrb" \
# ORB_SYMBOL="ORB" \
# ORB_TOKEN_URI="https://static.orb.land/staging/metadata" \
# npx hardhat run script/verify-Orb.ts --network goerli
