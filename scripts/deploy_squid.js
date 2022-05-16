const { utils } = require("ethers");
const { ethers } = require("hardhat");
const hre = require("hardhat");

const ROUTERS = {
  PANCAKE: "0x10ED43C718714eb63d5aA57B78B54704E256024E",
  PANCAKE_TESTNET: "0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3",
  UNISWAP: "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D",
  SUSHISWAP_TESTNET: "0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506",
  PANGALIN: "0xE54Ca86531e17Ef3616d22Ca28b0D458b6C89106",
};

const sleep = async (s) => {
  for (let i = s; i > 0; i--) {
    process.stdout.write(`\r \\ ${i} waiting..`);
    await new Promise((resolve) => setTimeout(resolve, 250));
    process.stdout.write(`\r | ${i} waiting..`);
    await new Promise((resolve) => setTimeout(resolve, 250));
    process.stdout.write(`\r / ${i} waiting..`);
    await new Promise((resolve) => setTimeout(resolve, 250));
    process.stdout.write(`\r - ${i} waiting..`);
    await new Promise((resolve) => setTimeout(resolve, 250));
    if (i === 1) process.stdout.clearLine();
  }
};
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

/*
Contract Owner - 0xDa34B441b85259A0d75Ca88848674FC4864d266f
Charity Wallet - 0x4a295DDd39d00B478c78f4c001B05426e4e86139
Marketing & Development - 0x545AbE7f40758AB78270d9Ce2c7d2CFB7686B239
Team Reserve - 0xed0be63249bF91d538da888f6c6Bda2d2273cC94
BuyBack Wallet - 0x024A6b416354611a0B179F2FB9BCd19FB0Fab0bf
*/

let owner = "0xDa34B441b85259A0d75Ca88848674FC4864d266f";

let charityWallet = "0x4a295DDd39d00B478c78f4c001B05426e4e86139";
let marketingWallet = "0x545AbE7f40758AB78270d9Ce2c7d2CFB7686B239";
let teamWallet = "0xed0be63249bF91d538da888f6c6Bda2d2273cC94";
let vaultWallet = "0x024A6b416354611a0B179F2FB9BCd19FB0Fab0bf";

let busdAddress = "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56";

async function main() {

  const [deployer] = await ethers.getSigners();
  const router = ROUTERS.PANCAKE;

  await hre.run("verify:verify", {
    address: "0x597Ad653B92255dba353c5375C727b363Ba042A2",
    constructorArguments: ["1000000000", router, "0x98a4CD7a7d9c1978C497A4f2AEe0B7503444d6B3", vaultWallet, owner],
  });
  return;

  const FeeSplitter = await ethers.getContractFactory("FeeSplitter");
  const feeSplitter = await FeeSplitter.deploy(charityWallet, marketingWallet, teamWallet);
  await feeSplitter.deployed();
  console.log("feeSplitter", feeSplitter.address);

  const Squidoshi = await ethers.getContractFactory("Squidoshi");
  const squidoshi = await Squidoshi.deploy("1000000000", router, feeSplitter.address, vaultWallet, owner);
  await squidoshi.deployed();
  console.log("squidoshi", squidoshi.address);


  const reflectorContract = await ethers.getContractFactory("SquidoshiReflector");
  const reflector = await reflectorContract.deploy(squidoshi.address, router, ZERO_ADDRESS);
  await reflector.deployed();
  console.log("reflector", reflector.address);

  const lot1Contract = await ethers.getContractFactory("SquidoshiSmartLottery");
  const log1 = await lot1Contract.deploy(squidoshi.address, router, ZERO_ADDRESS);
  await log1.deployed();
  console.log("log1", log1.address);

  const lotContract = await ethers.getContractFactory("SquidoshiSmartLotteryV2");
  const log = await lotContract.deploy(squidoshi.address, log1.address, router, ZERO_ADDRESS);
  await log.deployed();
  console.log("lottery", log.address);

  await (await squidoshi.connect(deployer).init(reflector.address, log.address, busdAddress)).wait();
  console.log("init....");
  await (await squidoshi.connect(deployer).addBUSDPair(busdAddress)).wait();
  console.log("Pair added....");
  // await (await squidoshi.connect(deployer).openTrading()).wait();
  // console.log("open trading");

  const Staking = await ethers.getContractFactory("Staking");
  const staking = await Staking.deploy(
    squidoshi.address, busdAddress, 6, 11, 20, router
  );
  await staking.deployTransaction.wait()
  console.log("Staking address:", staking.address);

  await sleep(100);

  await hre.run("verify:verify", {
    address: feeSplitter.address,
    constructorArguments: [charityWallet, marketingWallet, teamWallet],
  });

  await hre.run("verify:verify", {
    address: squidoshi.address,
    constructorArguments: ["1000000000", router, feeSplitter.address, vaultWallet, owner],
  });
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
