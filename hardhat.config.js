require("@nomiclabs/hardhat-waffle");

const PRIVATE_KEY = "aeea8cb8e50f141ac7bdcfa985c2d28958463799d90014f937cbec6f2e53ebda";

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: "0.8.4",
  networks: {
  	jingshi: {
      url: `http://120.92.137.203:9009/`,
      accounts: [`0x${PRIVATE_KEY}`],
    },
    mainnet: {
      url: `https://jsonrpc.maiziqianbao.net`,
      accounts: [`0x${PRIVATE_KEY}`],
    },
    rinkeby: {
      url: `https://rinkeby.infura.io/v3/f55e80a3523b48feb3ef8e4a0c9f5bcc`,
      accounts: [`0x${PRIVATE_KEY}`],
    },
    clover: {
    	url: `https://rpc.clover.finance`,
      accounts: [`0x${PRIVATE_KEY}`],
    }
  }
};
