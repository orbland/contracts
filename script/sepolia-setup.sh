npx hardhat run script/deploy-PaymentSplitterImplementation.ts --network sepolia
# Payment Splitter implementation deployed to: 0xF149432073BE88524D90669DA79684B9eB26F372

npx hardhat run script/deploy-OrbInvocationRegistry.ts --network sepolia
# Orb Invocation Registry deployed to: 0x573425F92bc94B00372Bc9Ef0DE95f393e0B6b1B
# Orb Invocation Registry Implementation deployed to: 0x89f41A34B5d7B8d03ae1508ee7476c066b02847A

ORB_INVOCATION_REGISTRY_ADDRESS=0x573425F92bc94B00372Bc9Ef0DE95f393e0B6b1B \
PAYMENT_SPLITTER_IMPLEMENTATION_ADDRESS=0xF149432073BE88524D90669DA79684B9eB26F372 \
npx hardhat run script/deploy-OrbPond.ts --network sepolia
# Orb Pond deployed to: 0xa1Db3a8fE99e065c37BEd990D4321De047fbb281
# Orb Pond Implementation deployed to: 0xFe2636c58DC08F0117690A80f24335Ef96e8eA0d

ORB_POND_ADDRESS=0xa1Db3a8fE99e065c37BEd990D4321De047fbb281 \
npx hardhat run script/upgrade-OrbPondV2.ts --network sepolia
# Orb Pond V2 Implementation deployed to: 0xda9FF398707D90af0Fa6885E4E1576abAd7c4286
# Orb Pond upgraded to V2: 0xa1Db3a8fE99e065c37BEd990D4321De047fbb281

npx hardhat run script/deploy-OrbImplementation.ts --network sepolia
# Orb V1 implementation deployed to: 0xd09dEA92b1608bD3F9451ff2fa451688ce771EE6

npx hardhat run script/deploy-OrbV2Implementation.ts --network sepolia
# Orb V2 implementation deployed to: 0xb88923709222183dd17D58c6d6c78C77a7b4AC7a

ORB_POND_ADDRESS=0xa1Db3a8fE99e065c37BEd990D4321De047fbb281 \
ORB_V1_IMPLEMENTATION=0xd09dEA92b1608bD3F9451ff2fa451688ce771EE6 \
ORB_V2_IMPLEMENTATION=0xb88923709222183dd17D58c6d6c78C77a7b4AC7a \
npx hardhat run script/call-registerOrbVersions.ts --network sepolia

PLATFORM_WALLET=0xa46598F1446e64AB6609C2Bea970335D9d8099FE \
PLATFORM_FEE=500 \
npx hardhat run script/deploy-OrbInvocationTipJar.ts --network sepolia
# Orb Invocation Tip Jar deployed to: 0x7ef56321ED1861e20CD3aEe923bd47230c63D094
# Orb Invocation Tip Jar Implementation deployed to: 0x850Fd63A25990f5F1191dD4FD52edD0F391a6BC9

# Contract Verifications

PAYMENT_SPLITTER_ADDRESS=0xF149432073BE88524D90669DA79684B9eB26F372 \
npx hardhat run script/verify-PaymentSplitterImplementation.ts --network sepolia

ORB_INVOCATION_REGISTRY_ADDRESS=0x89f41A34B5d7B8d03ae1508ee7476c066b02847A \
npx hardhat run script/verify-OrbInvocationRegistryImplementation.ts --network sepolia

ORB_POND_ADDRESS=0xFe2636c58DC08F0117690A80f24335Ef96e8eA0d \
npx hardhat run script/verify-OrbPondImplementation.ts --network sepolia

ORB_POND_ADDRESS=0xda9FF398707D90af0Fa6885E4E1576abAd7c4286 \
npx hardhat run script/verify-OrbPondV2Implementation.ts --network sepolia

ORB_ADDRESS=0xd09dEA92b1608bD3F9451ff2fa451688ce771EE6 \
npx hardhat run script/verify-OrbImplementation.ts --network sepolia

ORB_ADDRESS=0xb88923709222183dd17D58c6d6c78C77a7b4AC7a \
npx hardhat run script/verify-OrbV2Implementation.ts --network sepolia

ORB_INVOCATION_TIP_JAR_ADDRESS=0x850Fd63A25990f5F1191dD4FD52edD0F391a6BC9 \
npx hardhat run script/verify-OrbInvocationTipJarImplementation.ts --network sepolia

# Transfer Ownership

ORB_INVOCATION_REGISTRY_ADDRESS=0x573425F92bc94B00372Bc9Ef0DE95f393e0B6b1B \
SAFE_ADDRESS=0x84EC4e9e9897C3EA25cfe9d34Ed427074aDAAA8D \
npx hardhat run script/transferOwnership-OrbInvocationRegistry.ts --network sepolia

ORB_POND_ADDRESS=0xa1Db3a8fE99e065c37BEd990D4321De047fbb281 \
SAFE_ADDRESS=0x84EC4e9e9897C3EA25cfe9d34Ed427074aDAAA8D \
npx hardhat run script/transferOwnership-OrbPond.ts --network sepolia

ORB_INVOCATION_TIP_JAR_ADDRESS=0x7ef56321ED1861e20CD3aEe923bd47230c63D094 \
SAFE_ADDRESS=0x84EC4e9e9897C3EA25cfe9d34Ed427074aDAAA8D \
npx hardhat run script/transferOwnership-OrbInvocationTipJar.ts --network sepolia

# Orb Proxy Verification

# ORB_IMPLEMENTATION_ADDRESS=0x10b0e79D892Be4345F800501378F1eD144824Ae1 \
# ORB_ADDRESS=0x7aAd4004576482a952B8382f0DcF71D64CF77f25 \
# BENEFICIARY=0xAE684f43F12758ED4eE6016Ae8cbfb61416B618a \
# ORB_NAME="TestOrb" \
# ORB_SYMBOL="ORB" \
# ORB_TOKEN_URI="https://static.orb.land/staging/metadata" \
# npx hardhat run script/verify-Orb.ts --network goerli
