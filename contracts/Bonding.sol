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
    IERC20 amaticb;
    ISKU skusd;
    IERC20 public sikka;

    struct Info {
        uint loanAmount;
        uint borrowAmount;
        uint interestAmount;
        uint interestSettle;
    }

    mapping(address => Info) users;

    uint constant MAG = 1e18; 

    uint public totalLoan;
    uint public totalBorrow;
    address public oracle;
    address public earn;
    uint public loanRate;
    uint public liquidateRate;
    uint public interestRate;

    uint public lastUpdateTime;
    uint public interestPerBorrow;

    using SafeERC20 for IERC20;
    event SetValue(uint loanRate, uint liquidateRate);
    event PreMint(address to, uint amount);
    event Bond(address user, uint amountInAMATICB, uint amountOutUSD, uint priceAMATICB, uint priceUSD, uint loanRate);
    event Unbond(address user, uint amountInUSD, uint amountInAMATICB);
    event PayInterest(address payer, address user, uint amount);
    event Liquidate(address bondUser, address liquidateUser, uint amountInUSD, uint amountInAMATICB, uint priceAMATICB, uint priceUSD, uint liquidateRate);
    event Withdraw(uint amount, address to);

    constructor(IERC20 _amaticb, ISKU _skusd, IERC20 _sikka, address _oracle, address _earn) {
        amaticb = _amaticb;
        skusd = _skusd;
        oracle = _oracle;
        sikka = _sikka;
        earn = _earn;
    }

    function setRate(uint _loanRate, uint _liquidateRate, uint _interestRate) update(address(0)) external onlyOwner {
        require(_loanRate > 0 && _loanRate <= 1e18, "INVALID LOAN RATE");
        require(_liquidateRate > 0 && _liquidateRate <= 1e18 && _liquidateRate >= _loanRate, "INVALID LIQUIDATE RATE");

        loanRate = _loanRate;
        liquidateRate = _liquidateRate;
        interestRate = _interestRate;

        emit SetValue(loanRate, liquidateRate);
    }

    function setEarn(address _earn) external onlyOwner {
        earn = _earn;
    }

    modifier update(address userAddr) {
        if(totalBorrow > 0) {
            uint interestAdd = interestRate.mul(totalBorrow).mul(block.number.sub(lastUpdateTime)).div(MAG);
            interestPerBorrow = interestPerBorrow.add(interestAdd.mul(MAG).div(totalBorrow));
        }

        lastUpdateTime = block.number;

        if(userAddr != address(0)) {
            Info storage user = users[msg.sender];
            user.interestAmount = user.interestAmount.add(interestPerBorrow.sub(user.interestSettle).mul(user.borrowAmount).div(MAG));
            user.interestSettle = interestPerBorrow;
        }   
        _;
    }

    modifier noPause() {
        require(loanRate > 0 && liquidateRate > 0, "NOT SETUP OR PAUSE");
        _;
    }

    function calculateInterest(address userAddr) view public returns(uint interestSikka) {
        if(totalBorrow == 0) {
            return 0;
        }
        uint interestAdd = interestRate.mul(totalBorrow).mul(block.number.sub(lastUpdateTime)).div(MAG);
        uint _interestPerBorrow = interestPerBorrow.add(interestAdd.mul(MAG).div(totalBorrow));

        uint priceSikka = IOracle(oracle).getPrice("SIKKA");
        uint priceUSD = IOracle(oracle).getPrice("SKUSD");
        uint newInterest = _interestPerBorrow.sub(users[userAddr].interestSettle).mul(users[userAddr].borrowAmount).div(MAG);
        uint interestUSD = users[userAddr].interestAmount.add(newInterest);
        return interestUSD.mul(priceUSD).div(priceSikka);
    }

    function bond(uint amountInAMATICB, uint amountSKUSDMin) noPause update(msg.sender) external returns (uint amountOutUSD) {
        uint priceAMATICB = IOracle(oracle).getPrice("AMATICB");
        uint priceUSD = IOracle(oracle).getPrice("SKUSD");

        amaticb.safeTransferFrom(msg.sender, address(this), amountInAMATICB);

        amountOutUSD = amountInAMATICB.mul(priceUSD).div(priceAMATICB).mul(loanRate).div(MAG);
        require(amountOutUSD > amountSKUSDMin, "INVALID USD AMOUNT");

        Info storage user = users[msg.sender];
        user.loanAmount = user.loanAmount.add(amountInAMATICB);
        user.borrowAmount = user.borrowAmount.add(amountOutUSD);
        totalLoan = totalLoan.add(amountInAMATICB);
        totalBorrow = totalBorrow.add(amountOutUSD);

        require(amountOutUSD >= amountSKUSDMin, "SLIP");

        skusd.mint(msg.sender, amountOutUSD);
        emit Bond(msg.sender, amountInAMATICB, amountOutUSD, priceAMATICB, priceUSD, loanRate);
    }

    function payInterest(address userAddr) private {
        uint priceSikka = IOracle(oracle).getPrice("SIKKA");
        uint priceUSD = IOracle(oracle).getPrice("SKUSD");

        if(users[userAddr].interestAmount > 0) {
            uint interestSikka = users[userAddr].interestAmount.mul(priceUSD).div(priceSikka);
            
            emit PayInterest(msg.sender, userAddr, users[userAddr].interestAmount);
            users[userAddr].interestAmount = 0;
            sikka.safeTransferFrom(msg.sender, earn, interestSikka);
        } 
    }

    function unbond(uint amountInUSD, uint amountOutAMATICBMin) noPause update(msg.sender) external returns (uint amountOutAMATICB) {
        Info storage user = users[msg.sender];
        require(amountInUSD <= user.borrowAmount, "INVALID UNBOND AMOUNT");

        payInterest(msg.sender);

        amountOutAMATICB = amountInUSD.mul(user.loanAmount).div(user.borrowAmount);
        user.borrowAmount = user.borrowAmount.sub(amountInUSD);
        user.loanAmount = user.loanAmount.sub(amountOutAMATICB);

        totalLoan = totalLoan.sub(amountOutAMATICB);
        totalBorrow = totalBorrow.sub(amountInUSD);

        require(amountOutAMATICB >= amountOutAMATICBMin, "SLIP");

        skusd.burn(msg.sender, amountInUSD);
        amaticb.safeTransfer(msg.sender, amountOutAMATICB);
        emit Unbond(msg.sender, amountInUSD, amountOutAMATICB);
    }

    function liquidate(address userAddr, uint amountInUSD, uint amountOutAMATICBMin) noPause update(userAddr)  external returns (uint amountOutAMATICB) {
        Info storage user = users[userAddr];
        uint priceAMATICB = IOracle(oracle).getPrice("AMATICB");
        uint priceUSD = IOracle(oracle).getPrice("SKUSD");

        uint valueLoan = user.loanAmount.mul(priceAMATICB).div(MAG);
        uint valueBorrow = user.borrowAmount.mul(priceUSD).div(MAG).add(user.interestAmount);
        require(valueLoan.mul(liquidateRate).div(MAG) <= valueBorrow, "CAN NOT LIQUIDATE NOW");

        payInterest(userAddr);

        amountOutAMATICB = amountInUSD.mul(user.loanAmount).div(user.borrowAmount);
        user.borrowAmount = user.borrowAmount.sub(amountInUSD);
        user.loanAmount = user.loanAmount.sub(amountOutAMATICB);

        require(amountOutAMATICB >= amountOutAMATICBMin, "SLIP");

        skusd.burn(msg.sender, amountInUSD);
        amaticb.safeTransfer(msg.sender, amountOutAMATICB);
        emit Liquidate(userAddr, msg.sender, amountInUSD, amountOutAMATICB, priceAMATICB, priceUSD, liquidateRate);
    }

    function withdraw(uint amount, address to) onlyOwner external {
        require(amaticb.balanceOf(address(this)) >= amount.add(totalLoan), "NOT ENOUGH TOKEN");
        amaticb.safeTransfer(msg.sender, amount);

        emit Withdraw(amount, to);
    }
}
