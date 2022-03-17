const { expect } = require("chai");
const { ethers } = require("hardhat");
let BN = require("bignumber.js");

function toTokenAmount(amount, decimals = 18) {
    return new BN(amount).multipliedBy(new BN("10").pow(decimals)).toFixed()
}

const toMathAmount = (amount, decimals = 18) => new BN(amount.toString()).dividedBy(new BN(Math.pow(10, decimals))).toFixed();

describe("Bond", function () {
  let abnb, skusd, bonding, oracle;
  let developer, user1, feeTo;

  before(async () => {
      [developer, user1, feeTo] = await ethers.getSigners()

      let ABNB = await ethers.getContractFactory("aBNBb");
      abnb = await ABNB.deploy();

      let SKU = await ethers.getContractFactory("SKU");
      skusd = await SKU.deploy("SKUSD", "SKUSD");

      let Oracle = await ethers.getContractFactory("Oracle");
      oracle = await Oracle.deploy();

      let Bonding = await ethers.getContractFactory("Bonding");
      bonding = await Bonding.deploy(abnb.address, skusd.address, oracle.address);

      await (await skusd.addPermission(bonding.address)).wait();
      await (await abnb.initialize(developer.address)).wait();

      await (await abnb.mint(user1.address, toTokenAmount(1000000))).wait();
      await (await bonding.setValue(toTokenAmount(0.5), toTokenAmount(0.8))).wait();
      await (await oracle.setPrice(["ABNB", "SKUSD"], [toTokenAmount(1), toTokenAmount(1)]));

      await abnb.connect(user1).approve(bonding.address, toTokenAmount(10000000000));
  });

  async function logBalance(wallet) {
      let abnbBalance = await abnb.balanceOf(wallet.address);
      let usdBalance = await skusd.balanceOf(wallet.address);

      // console.log(`delta ${await bonding.delta()}`);
      console.log(`abnb: ${toMathAmount(abnbBalance)} usd: ${toMathAmount(usdBalance)}`);
  }

  it("simple bond", async function () {
        await logBalance(user1);

        await bonding.connect(user1).bond(toTokenAmount(100), 0);
        await logBalance(user1);

        await bonding.connect(user1).unbond(toTokenAmount(20), 0);
        await logBalance(user1);

        await skusd.connect(user1).transfer(developer.address, toTokenAmount(30));
        await (await oracle.setPrice(["ABNB", "SKUSD"], [toTokenAmount(0.6), toTokenAmount(1)]));
        await bonding.liquidate(user1.address, toTokenAmount(20), 0);
        await logBalance(developer);

        await (await abnb.mint(user1.address, toTokenAmount(100))).wait();
        await logBalance(user1);
   });
});
