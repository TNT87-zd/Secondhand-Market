const hre = require("hardhat");
const fs = require("fs");

async function main() {
  const [arbiter, seller, buyer] = await hre.ethers.getSigners();
  const deployer = arbiter;
  const market = await (await hre.ethers.getContractFactory("Marketplace")).deploy(arbiter.address);
  await market.waitForDeployment();

  const address = await market.getAddress();
  console.log("Marketplace:", address);
  console.log("Escrow     :", await market.escrow());
  console.log("Arbiter    :", arbiter.address);

  // Xuất địa chỉ + ABI cho front-end
  const artifact = await hre.artifacts.readArtifact("Marketplace");
  fs.writeFileSync(
    "frontend/contract.js",
    "const CONTRACT = " + JSON.stringify({ address, abi: artifact.abi }, null, 2) + ";"
  );
}

main().catch((e) => { console.error(e); process.exitCode = 1; });