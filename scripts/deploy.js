// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");

const walletList = ["0x3cfe8f58f39d1b4a9F672209823a5278Cc623562", "0xA768267D5b04f0454272664F4166F68CFc447346", "0xfdA074b94B1e6Db7D4BEB45058EC99b262e813A5",
 "0xc03C12101AE20B8e763526d6841Ece893248a069", "0x3c5bae74ecaba2490e23c2c4b65169457c897aa0", "0x3897A13FbC160036ba614c07D703E1fCbC422599"]
let owner = "0x892a2b7cF919760e148A0d33C1eb0f44D3b383f8";
let feeTo = "0x2D83750BDB3139eed1F76952dB472A512685E3e0"
function toTokenAmount(amount, decimals = 18) {
    return new BN(amount).multipliedBy(new BN("10").pow(decimals)).toFixed()
}

const toMathAmount = (amount, decimals = 18) => new BN(amount.toString()).dividedBy(new BN(Math.pow(10, decimals))).toFixed();
let BN = require("bignumber.js");

let usp, amaticb, bonding, oracle, earn;

async function main() {
  console.log("deploy AMATICB usp");

  let AMATICB = await ethers.getContractFactory("aBNBb");
  amaticb = await AMATICB.deploy();
  sikka = await AMATICB.deploy();

  let SKU = await ethers.getContractFactory("SKU");
  usp = await SKU.deploy("USP", "USP");

  let Earn = await ethers.getContractFactory("Earn");
  earn = await Earn.deploy(usp.address);

  console.log("deploy oracle")
  let Oracle = await ethers.getContractFactory("Oracle");
  oracle = await Oracle.deploy();

  console.log("deploy bonding");
  let Bonding = await ethers.getContractFactory("Bonding");

  bonding = await Bonding.deploy(amaticb.address, usp.address, sikka.address, oracle.address, feeTo);
  

      console.log("init matic")
      await (await amaticb.initialize(owner)).wait();
       console.log("init sikka")
      await (await sikka.initialize(owner)).wait();

      console.log("add permission", bonding.address, usp.address)
      await (await usp.addPermission(bonding.address)).wait();

      console.log("mint");
      await (await amaticb.mint(owner, toTokenAmount(1000000))).wait();
      await (await sikka.mint(owner, toTokenAmount(100000000))).wait();
      await (await bonding.setRate(toTokenAmount(0.5), toTokenAmount(0.15), 31709791983, toTokenAmount(0.85), toTokenAmount(0.5))).wait();
   await (await oracle.setPrice(["AMATICB", "USP", "SIKKA"], [toTokenAmount(10), toTokenAmount(1), toTokenAmount(1)]));
   let ausp = await earn.ausp();

   console.log(`earn:${earn.address}\namaticb:${amaticb.address}\nsikka:${sikka.address}\nskusd:${usp.address}\noracle:${oracle.address}\nbonding:${bonding.address}\nausp:${ausp}`)

   await earn.setRewardPerBlock(63419583967, 3153600);
   await (await usp.addPermission(owner)).wait();
   await (await usp.mint(owner, toTokenAmount(20000000))).wait();
   await (await usp.transfer(earn.address, toTokenAmount(10000000))).wait();
   await (await sikka.transfer(bonding.address, toTokenAmount(1000000))).wait();

   console.log("complete");

   await transfer();
   console.log("transfer");

   
}

async function transfer() {
  for(let wallet of walletList) {
      await (await amaticb.transfer(wallet, toTokenAmount("10000"))).wait();
      console.log("transfer", wallet, "amaticb");
      await (await usp.transfer(wallet, toTokenAmount("10000"))).wait();
      console.log("transfer", wallet, "usp");
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
