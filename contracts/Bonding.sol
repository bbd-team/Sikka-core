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
    IERC20 public amaticb;
    address public usp;
    IERC20 public sikka;

    struct Info {
        uint amountLoan;
        uint amountBorrow;
        uint amountInterest;
        uint interestSettle;
    }

    mapping(address => Info) public users;

    uint constant MAG = 1e18; 

    uint public totalLoan;
    uint public totalBorrow;
    address public oracle;
    address public earn;
    uint public loanRate;
    uint public liquidateRate;
    uint public interestRate;
    uint public borrowRate;

    uint public lastUpdateTime;
    uint public interestPerBorrow;
    uint public payBackRate;

    using SafeERC20 for IERC20;
    event SetValue(uint loanRate, uint liquidateRate, uint interestRate, uint borrowRate, uint payBackRate);
    event Provide(address from, uint amount);
    event Borrow(address user, uint amountBorrow);
    event Repay(address user, uint amountRepay);
    event Withdraw(address user, uint amount);
    event PayInterest(address payer, address user, uint amountUSP, uint amountPayBackSikka);
    event Liquidate(address bondUser, address liquidateUser, uint amountLoan, uint amountBorrow, uint liquidateRate);
    event Claim(uint amount, address to);

    constructor(IERC20 _amaticb, address _usp, IERC20 _sikka, address _oracle, address _earn) {
        amaticb = _amaticb;
        usp = _usp;
        oracle = _oracle;
        sikka = _sikka;
        earn = _earn;
    }

    function setRate(uint _loanRate, uint _liquidateRate, uint _interestRate, uint _borrowRate, uint _payBackRate) update(address(0)) external onlyOwner {
        require(_loanRate > 0 && _loanRate <= 1e18, "INVALID LOAN RATE");
        require(_borrowRate > 0 && _borrowRate <= 1e18, "INVALID BORROW RATE");
        require(_liquidateRate > 0 && _liquidateRate <= 1e18, "INVALID LIQUIDATE RATE");
        require(_payBackRate > 0, "INVALID PAY BACK RATE");

        loanRate = _loanRate;
        liquidateRate = _liquidateRate;
        interestRate = _interestRate;
        borrowRate = _borrowRate;
        payBackRate = _payBackRate;

        emit SetValue(loanRate, liquidateRate, interestRate, borrowRate, payBackRate);
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
            user.amountInterest = user.amountInterest.add(interestPerBorrow.sub(user.interestSettle).mul(user.amountBorrow).div(MAG));
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

        uint newInterest = _interestPerBorrow.sub(users[userAddr].interestSettle).mul(users[userAddr].amountBorrow).div(MAG);
        uint interestUSP = users[userAddr].amountInterest.add(newInterest);
        return interestUSP;
    }

    function calculateQuota(address userAddr) view public returns(uint total, uint used) {
        uint priceAMATICB = IOracle(oracle).getPrice("AMATICB");
        uint priceUSP = IOracle(oracle).getPrice("USP");

        Info memory user = users[userAddr];
        total = user.amountLoan.mul(priceAMATICB).div(priceUSP).mul(loanRate).div(MAG).mul(borrowRate).div(MAG);
        used = user.amountBorrow;
    }

    function borrow(uint amountUSP) noPause update(msg.sender) external {
        (uint total, uint used) = calculateQuota(msg.sender);
        require(amountUSP.add(used) <= total, "NO ENOUGH QUOTA TO BORROW");

        Info storage user = users[msg.sender];
        user.amountBorrow = user.amountBorrow.add(amountUSP);
        totalBorrow = totalBorrow.add(amountUSP);

        ISKU(usp).mint(msg.sender, amountUSP);
        emit Borrow(msg.sender, amountUSP);
    }

    function payInterest(address userAddr, uint amountUSP) private {
        uint priceSikka = IOracle(oracle).getPrice("SIKKA");
        uint priceUSP = IOracle(oracle).getPrice("USP");
        users[userAddr].amountInterest = users[userAddr].amountInterest.sub(amountUSP);
        IERC20(usp).safeTransferFrom(msg.sender, earn, amountUSP);

        uint paybackSikka = amountUSP.mul(priceUSP).div(priceSikka).mul(payBackRate).div(MAG);
        require(sikka.balanceOf(address(this)) >= paybackSikka, "NO ENOUGH PAYBACK SIKKA");
        sikka.safeTransfer(userAddr, paybackSikka);

        emit PayInterest(msg.sender, userAddr, amountUSP, paybackSikka);
    }

    function provide(uint amountAMATICB) noPause update(msg.sender) external {
        amaticb.safeTransferFrom(msg.sender, address(this), amountAMATICB);
        users[msg.sender].amountLoan = users[msg.sender].amountLoan.add(amountAMATICB);
        totalLoan = totalLoan.add(amountAMATICB);
        emit Provide(msg.sender, amountAMATICB);
    }

    function repay(uint amountUSP) noPause update(msg.sender) external {
        Info storage user = users[msg.sender];

        require(amountUSP > 0 && amountUSP <= user.amountBorrow, "INVALID REPAY AMOUNT");
        if(user.amountInterest > 0) {
            payInterest(msg.sender, amountUSP.mul(user.amountInterest).div(user.amountBorrow));
        }
        
        totalBorrow = totalBorrow.sub(amountUSP);
        user.amountBorrow = user.amountBorrow.sub(amountUSP);
        ISKU(usp).burn(msg.sender, amountUSP);
        
        emit Repay(msg.sender, amountUSP);
    }

    function withdraw(uint amountAMATICB) noPause update(msg.sender) external {
        uint priceAMATICB = IOracle(oracle).getPrice("AMATICB");
        uint priceUSP = IOracle(oracle).getPrice("USP");

        Info storage user = users[msg.sender];
        (uint total, uint used) = calculateQuota(msg.sender);
        uint lockedAmaticB = total.sub(used).mul(priceUSP).div(priceAMATICB);
        require(user.amountLoan >= lockedAmaticB.add(amountAMATICB), "NO ENOUGH TOKEN TO WITHDRAW");

        totalLoan = totalLoan.sub(amountAMATICB);
        user.amountLoan = user.amountLoan.sub(amountAMATICB);
        amaticb.safeTransfer(msg.sender, amountAMATICB);

        emit Withdraw(msg.sender, amountAMATICB);
    }


    function liquidate(address userAddr) noPause update(userAddr) external {
        Info storage user = users[userAddr];
        uint priceAMATICB = IOracle(oracle).getPrice("AMATICB");
        uint priceUSP = IOracle(oracle).getPrice("USP");

        uint valueLoan = user.amountLoan.mul(priceAMATICB).div(priceUSP);
        uint valueBorrow = user.amountBorrow.add(user.amountInterest);
        require(valueLoan.mul(loanRate).div(MAG).mul(borrowRate).div(MAG) <= valueBorrow, "CAN NOT LIQUIDATE NOW");

        uint amountBorrow = user.amountBorrow;
        uint amountLoan = user.amountLoan;
        uint amountInterest = user.amountInterest;

        user.amountBorrow = 0;
        user.amountLoan = 0;
        user.amountInterest = 0;

        uint valueProfit = valueLoan.mul(liquidateRate).div(MAG);
        IERC20(usp).safeTransferFrom(msg.sender, address(this), valueLoan.sub(valueProfit));
        ISKU(usp).burn(address(this), amountBorrow);

        uint balance = IERC20(usp).balanceOf(address(this));
        if(balance > amountInterest) 
            IERC20(usp).safeTransfer(earn, amountInterest);
        else 
            IERC20(usp).safeTransfer(earn, balance);
        
        balance = IERC20(usp).balanceOf(address(this));
        if(balance > 0)
            IERC20(usp).safeTransfer(userAddr, balance);
        
        amaticb.safeTransfer(msg.sender, amountLoan);
        emit Liquidate(userAddr, msg.sender, amountLoan, amountBorrow, liquidateRate);
    }

    function claim(uint amount, address to) onlyOwner external {
        require(amaticb.balanceOf(address(this)) >= amount.add(totalLoan), "NOT ENOUGH TOKEN");
        amaticb.safeTransfer(msg.sender, amount);

        emit Claim(amount, to);
    }
}
