const { expect } = require("chai");
const { ethers } = require("hardhat");
let BN = require("bignumber.js");

function toTokenAmount(amount, decimals = 18) {
    return new BN(amount).multipliedBy(new BN("10").pow(decimals)).toFixed()
}

const toMathAmount = (amount, decimals = 18) => new BN(amount.toString()).dividedBy(new BN(Math.pow(10, decimals))).toFixed();

describe("Bond", function () {
  let amaticb, usp, bonding, oracle, sikka, earn;
  let developer, user1, feeTo;

  before(async () => {
      [developer, user1, feeTo] = await ethers.getSigners()

      let AMATICB = await ethers.getContractFactory("aBNBb");
      amaticb = await AMATICB.deploy();
      sikka = await AMATICB.deploy();

      let SKU = await ethers.getContractFactory("SKU");
      usp = await SKU.deploy("USP", "USP");

      let Earn = await ethers.getContractFactory("Earn");
      earn = await Earn.deploy(usp.address);

      let Oracle = await ethers.getContractFactory("Oracle");
      oracle = await Oracle.deploy();

      let Bonding = await ethers.getContractFactory("Bonding");
      bonding = await Bonding.deploy(amaticb.address, usp.address, sikka.address, oracle.address, feeTo.address);

      await (await usp.addPermission(bonding.address)).wait();
      await (await amaticb.initialize(developer.address)).wait();
      await (await sikka.initialize(developer.address)).wait();

      await (await amaticb.mint(user1.address, toTokenAmount(1000000))).wait();
      await (await sikka.mint(user1.address, toTokenAmount(1000000))).wait();
      await (await bonding.setRate(toTokenAmount(0.5), toTokenAmount(0.15), toTokenAmount(0.1), toTokenAmount(0.95))).wait();
      await (await oracle.setPrice(["AMATICB", "USP", "SIKKA"], [toTokenAmount(10), toTokenAmount(1), toTokenAmount(1)]));

      await amaticb.connect(user1).approve(bonding.address, toTokenAmount(10000000000));
      await sikka.connect(user1).approve(bonding.address, toTokenAmount(10000000000));
      await usp.connect(user1).approve(earn.address, toTokenAmount(10000000000));

      await (await usp.addPermission(developer.address)).wait();
      await (await usp.mint(user1.address, toTokenAmount(10000000))).wait();
      await earn.setRewardPerBlock(toTokenAmount(0.1));
      await (await usp.connect(user1).transfer(earn.address, toTokenAmount(10000000))).wait();
  });

  async function logBalance(wallet) {
      let amaticbBalance = await amaticb.balanceOf(wallet.address);
      let usdBalance = await usp.balanceOf(wallet.address);

      let interest = await bonding.calculateInterest(user1.address);
      let iPerB = await bonding.interestPerBorrow();
      console.log(`interest ${toMathAmount(interest)} ${iPerB}`)

      let quota = await bonding.calculateQuota(user1.address);
      console.log(`quota ${toMathAmount(quota[0])} ${toMathAmount(quota[1])}`)


       let fee = await sikka.balanceOf(feeTo.address);
      console.log(`feeTo ${toMathAmount(fee)}`)

      // console.log(`delta ${await bonding.delta()}`);
      console.log(`amaticb: ${toMathAmount(amaticbBalance)} usd: ${toMathAmount(usdBalance)}`);
  }

  async function logEarnInfo() {
      let uspBalance = await usp.balanceOf(user1.address);

      let ausp = await hre.ethers.getContractAt("SKU", await earn.ausp());
      let auspBalance = await ausp.balanceOf(user1.address);
      console.log(`balance ${toMathAmount(uspBalance)} ${toMathAmount(auspBalance)}`)

      let price = await earn.price()
      console.log(`price ${toMathAmount(price)}`)
  }

  it("simple bond", async function () {
        await logBalance(user1);

        console.log("provide");
        await bonding.connect(user1).provide(toTokenAmount(30));
        await logBalance(user1);

        console.log("borrow");
        await bonding.connect(user1).borrow(toTokenAmount(100));
        await logBalance(user1);

        console.log("repay");
        await bonding.connect(user1).repay(toTokenAmount(50));
        await logBalance(user1);

        console.log("withdraw");
        await bonding.connect(user1).withdraw(toTokenAmount(20));
        await logBalance(user1);
   });

  it("simple earn", async function () {
        await logEarnInfo()
        await earn.connect(user1).stake(toTokenAmount(10));

        await logEarnInfo()
        await earn.connect(user1).withdraw(toTokenAmount(5))

        await logEarnInfo()
        await earn.connect(user1).stake(toTokenAmount(10));

        await logEarnInfo()
   });
});
