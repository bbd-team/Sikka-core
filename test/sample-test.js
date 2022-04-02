const { expect } = require("chai");
const { ethers } = require("hardhat");
let BN = require("bignumber.js");

function toTokenAmount(amount, decimals = 18) {
    return new BN(amount).multipliedBy(new BN("10").pow(decimals)).toFixed()
}

const toMathAmount = (amount, decimals = 18) => new BN(amount.toString()).dividedBy(new BN(Math.pow(10, decimals))).toFixed();

describe("Bond", function () {
  let amaticb, skusd, bonding, oracle, sikka;
  let developer, user1, feeTo;

  before(async () => {
      [developer, user1, feeTo] = await ethers.getSigners()

      let AMATICB = await ethers.getContractFactory("aBNBb");
      amaticb = await AMATICB.deploy();
      sikka = await AMATICB.deploy();

      let SKU = await ethers.getContractFactory("SKU");
      skusd = await SKU.deploy("SKUSD", "SKUSD");

      let Oracle = await ethers.getContractFactory("Oracle");
      oracle = await Oracle.deploy();

      let Bonding = await ethers.getContractFactory("Bonding");
      bonding = await Bonding.deploy(amaticb.address, skusd.address, sikka.address, oracle.address, feeTo.address);

      await (await skusd.addPermission(bonding.address)).wait();
      await (await amaticb.initialize(developer.address)).wait();
      await (await sikka.initialize(developer.address)).wait();

      await (await amaticb.mint(user1.address, toTokenAmount(1000000))).wait();
      await (await sikka.mint(user1.address, toTokenAmount(1000000))).wait();
      await (await bonding.setRate(toTokenAmount(0.5), toTokenAmount(0.8), toTokenAmount(0.1))).wait();
      await (await oracle.setPrice(["AMATICB", "SKUSD", "SIKKA"], [toTokenAmount(1), toTokenAmount(1), toTokenAmount(1)]));

      await amaticb.connect(user1).approve(bonding.address, toTokenAmount(10000000000));
      await sikka.connect(user1).approve(bonding.address, toTokenAmount(10000000000));
  });

  async function logBalance(wallet) {
      let amaticbBalance = await amaticb.balanceOf(wallet.address);
      let usdBalance = await skusd.balanceOf(wallet.address);

      let interest = await bonding.calculateInterest(user1.address);
      let iPerB = await bonding.interestPerBorrow();
      console.log(`interest ${toMathAmount(interest)} ${iPerB}`)

      let fee = await sikka.balanceOf(feeTo.address);
      console.log(`fee ${toMathAmount(fee)}`)

      // console.log(`delta ${await bonding.delta()}`);
      console.log(`amaticb: ${toMathAmount(amaticbBalance)} usd: ${toMathAmount(usdBalance)}`);
  }

  it("simple bond", async function () {
        await logBalance(user1);

        await bonding.connect(user1).bond(toTokenAmount(100), 0);
        await logBalance(user1);

        await bonding.connect(user1).bond(toTokenAmount(100), 0);
        await logBalance(user1);

        await bonding.connect(user1).bond(toTokenAmount(100), 0);
        await logBalance(user1);

        await bonding.connect(user1).unbond(toTokenAmount(20), 0);
        await logBalance(user1);

        await bonding.connect(user1).bond(toTokenAmount(100), 0);
        await logBalance(user1);

        // await skusd.connect(user1).transfer(developer.address, toTokenAmount(30));
        // await (await oracle.setPrice(["AMATICB", "SKUSD"], [toTokenAmount(0.6), toTokenAmount(1)]));
        // await bonding.liquidate(user1.address, toTokenAmount(20), 0);
        // await logBalance(developer);

        // await (await amaticb.mint(user1.address, toTokenAmount(100))).wait();
        // await logBalance(user1);
   });
});
