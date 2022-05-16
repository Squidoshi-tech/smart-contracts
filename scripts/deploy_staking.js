const ROUTERS = {
  PANCAKE: "0x10ED43C718714eb63d5aA57B78B54704E256024E",
  PANCAKE_TESTNET: "0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3",
  UNISWAP: "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D",
  SUSHISWAP_TESTNET: "0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506",
  PANGALIN: "0xE54Ca86531e17Ef3616d22Ca28b0D458b6C89106",
};

async function main() {

  const [deployer] = await ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);
  let deployerBalance = await deployer.getBalance();
  console.log("Account balance:", (ethers.utils.formatUnits(deployerBalance, 18)), "BNB");

  const router = ROUTERS.PANCAKE;
  let sqdiAddress = "0x7328A4d8Ff273b7D37048701843a46d30f7A9984";
  let busdAddress = "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56";

  const Staking = await ethers.getContractFactory("Staking");
  const staking = await Staking.deploy(
    sqdiAddress, busdAddress, 6, 11, 20, router
  );
  await staking.deployTransaction.wait()
  console.log("Staking address:", staking.address);

  // await hre.run("verify:verify", {
  //   address: staking.address,
  //   constructorArguments: [
  //     sqdiAddress, busdAddress, 6, 11, 20, router
  //   ],
  // });
  // console.log("Staking Verified");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
