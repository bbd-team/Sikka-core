//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./interfaces/ISKU.sol";
import "./interfaces/IOracle.sol";
import "hardhat/console.sol";

contract Bonding is Ownable {
	using SafeMath for uint;
    IERC20 abnb;
    ISKU skusd;

    struct Info {
        uint loanAmount;
        uint borrowAmount;
    }

    mapping(address => Info) users;

    uint constant MAG = 1e18; 

    uint public totalLoan;
    uint public totalBorrow;
    address public oracle;
    uint public loanRate;
    uint public liquidateRate;

    using SafeERC20 for IERC20;
    event SetValue(uint loanRate, uint liquidateRate);
    event PreMint(address to, uint amount);
    event Bond(address user, uint amountInABNB, uint amountOutUSD, uint priceABNB, uint priceUSD, uint loanRate);
    event Unbond(address user, uint amountInUSD, uint amountInABNB);
    event Liquidate(address bondUser, address liquidateUser, uint amountInUSD, uint amountInABNB, uint priceABNB, uint priceUSD, uint liquidateRate);
    event Withdraw(uint amount);

    constructor(IERC20 _abnb , ISKU _skusd, address _oracle) {
        abnb = _abnb;
        skusd = _skusd;
        oracle = _oracle;
    }

    function setValue(uint _loanRate, uint _liquidateRate) external onlyOwner {
        require(_loanRate > 0 && _loanRate <= 1e18, "INVALID LOAN VALUE");
        require(_liquidateRate > 0 && _liquidateRate <= 1e18 && _liquidateRate >= _loanRate, "INVALID LIQUIDATE VALUE");

        loanRate = _loanRate;
        liquidateRate = _liquidateRate;
        emit SetValue(loanRate, liquidateRate);
    }

    modifier noPause() {
        require(loanRate > 0 && liquidateRate > 0, "NOT SETUP OR PAUSE");
        _;
    }

    function bond(uint amountInABNB, uint amountSKUSDMin) noPause external returns (uint amountOutUSD) {
        uint priceABNB = IOracle(oracle).getPrice("ABNB");
    	uint priceUSD = IOracle(oracle).getPrice("SKUSD");

        abnb.safeTransferFrom(msg.sender, address(this), amountInABNB);

        amountOutUSD = amountInABNB.mul(priceUSD).div(priceABNB).mul(loanRate).div(MAG);
        require(amountOutUSD > amountSKUSDMin, "INVALID USD AMOUNT");

        users[msg.sender].loanAmount = users[msg.sender].loanAmount.add(amountInABNB);
        users[msg.sender].borrowAmount = users[msg.sender].borrowAmount.add(amountOutUSD);
        totalLoan = totalLoan.add(amountInABNB);
        totalBorrow = totalBorrow.add(amountOutUSD);

        require(amountOutUSD >= amountSKUSDMin, "SLIP");

        skusd.mint(msg.sender, amountOutUSD);
        emit Bond(msg.sender, amountInABNB, amountOutUSD, priceABNB, priceUSD, loanRate);
    }

    function unbond(uint amountInUSD, uint amountOutABNBMin) noPause external returns (uint amountOutABNB) {
        Info storage user = users[msg.sender];
        require(amountInUSD <= user.borrowAmount, "INVALID UNBOND AMOUNT");

        amountOutABNB = amountInUSD.mul(user.loanAmount).div(user.borrowAmount);
        user.borrowAmount = user.borrowAmount.sub(amountInUSD);
        user.loanAmount = user.loanAmount.sub(amountOutABNB);

        totalLoan = totalLoan.sub(amountOutABNB);
        totalBorrow = totalBorrow.sub(amountInUSD);

        require(amountOutABNB >= amountOutABNBMin, "SLIP");

        skusd.burn(msg.sender, amountInUSD);
        abnb.safeTransfer(msg.sender, amountOutABNB);
        emit Unbond(msg.sender, amountInUSD, amountOutABNB);
    }

    function liquidate(address userAddr, uint amountInUSD, uint amountOutABNBMin) noPause external returns (uint amountOutABNB) {
        Info storage user = users[userAddr];
        uint priceABNB = IOracle(oracle).getPrice("ABNB");
        uint priceUSD = IOracle(oracle).getPrice("SKUSD");

        uint valueLoan = user.loanAmount.mul(priceABNB).div(MAG);
        uint valueBorrow = user.borrowAmount.mul(priceUSD).div(MAG);
        require(valueLoan.mul(liquidateRate).div(MAG) <= valueBorrow, "CAN NOT LIQUIDATE NOW");

        amountOutABNB = amountInUSD.mul(user.loanAmount).div(user.borrowAmount);
        user.borrowAmount = user.borrowAmount.sub(amountInUSD);
        user.loanAmount = user.loanAmount.sub(amountOutABNB);

        require(amountOutABNB >= amountOutABNBMin, "SLIP");

        skusd.burn(msg.sender, amountInUSD);
        abnb.safeTransfer(msg.sender, amountOutABNB);
        emit Liquidate(userAddr, msg.sender, amountInUSD, amountOutABNB, priceABNB, priceUSD, liquidateRate);
    }

    function withdraw(uint amount) onlyOwner external {
        require(abnb.balanceOf(address(this)) >= amount.add(totalLoan), "NOT ENOUGH TOKEN");
        abnb.safeTransfer(msg.sender, amount);

        emit Withdraw(amount);
    }
}
