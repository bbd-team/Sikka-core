// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");

const walletList = ["0xA768267D5b04f0454272664F4166F68CFc447346", "0xfdA074b94B1e6Db7D4BEB45058EC99b262e813A5",
 "0xc03C12101AE20B8e763526d6841Ece893248a069", "0x3c5bae74ecaba2490e23c2c4b65169457c897aa0", "0x3897A13FbC160036ba614c07D703E1fCbC422599"]
let owner = "0x9F93bF49F2239F414cbAd0e4375c1e0E7AB833a2";
let feeTo = "0x2D83750BDB3139eed1F76952dB472A512685E3e0"
function toTokenAmount(amount, decimals = 18) {
    return new BN(amount).multipliedBy(new BN("10").pow(decimals)).toFixed()
}

const toMathAmount = (amount, decimals = 18) => new BN(amount.toString()).dividedBy(new BN(Math.pow(10, decimals))).toFixed();
let BN = require("bignumber.js");

let sku, amaticb, bonding, oracle;

async function main() {
  console.log("deploy AMATICB skusd");

  let AMATICB = await ethers.getContractFactory("aBNBb");
  amaticb = await AMATICB.deploy();
  sikka = await AMATICB.deploy();

  let SKU = await ethers.getContractFactory("SKU");
  skusd = await SKU.deploy("SKUSD", "SKUSD");

  console.log("deploy oracle")
  let Oracle = await ethers.getContractFactory("Oracle");
  oracle = await Oracle.deploy();

  console.log("deploy bonding");
  let Bonding = await ethers.getContractFactory("Bonding");

  bonding = await Bonding.deploy(amaticb.address, skusd.address, sikka.address, oracle.address, feeTo);
  console.log("init")
    

      await (await skusd.addPermission(bonding.address)).wait();
      await (await amaticb.initialize(owner)).wait();
      await (await sikka.initialize(owner)).wait();

      console.log("mint");
      await (await amaticb.mint(owner, toTokenAmount(1000000))).wait();
      await (await sikka.mint(owner, toTokenAmount(1000000))).wait();
      await (await bonding.setRate(toTokenAmount(0.5), toTokenAmount(0.8), "380517503805")).wait();
      await (await oracle.setPrice(["AMATICB", "SKUSD", "SIKKA"], [toTokenAmount(10), toTokenAmount(1), toTokenAmount(1)]));


   console.log(`amaticb:${amaticb.address}\nsikka:${sikka.address}\nskusd:${skusd.address}\noracle:${oracle.address}\nbonding:${bonding.address}`)
   await transfer();
   console.log("complete");
}

async function transfer() {
  for(let wallet of walletList) {
      await amaticb.transfer(wallet, toTokenAmount("10000"));
      await sikka.transfer(wallet, toTokenAmount("10000"));
      console.log("transfer", wallet);
  }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
