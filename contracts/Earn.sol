// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./base/Permission.sol";
import "hardhat/console.sol";

contract AUSP is ERC20, Ownable {
	constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {
	}

	function mint(address _to, uint256 _amount) external onlyOwner {
	   _mint(_to, _amount);
	}

	function burn(address _from, uint256 _amount) external onlyOwner {
	    _burn(_from, _amount);
	}
}

contract Earn is Ownable, ReentrancyGuard {
	using SafeMath for uint;
	AUSP public ausp;
	uint public rewardPerBlock;
	uint public lastUpdate;
	ERC20 public usp;
	uint public basePrice = 1e18;
	bool public staked = false;

	uint constant MAG = 1e18;
	using SafeERC20 for ERC20;
	uint public compoundTime;

	event SetRewardPerBlock(uint rewardPerBlock);
	event Stake(address user, uint amountInUSP, uint amountOutAUSP);
	event Withdraw(address user, uint amountInAUSP, uint amountOutUSP);
	event Take(uint amount, address to);

	constructor(ERC20 _usp) {
		ausp = new AUSP("AUSP", "AUSP");
		usp = _usp;
	}

	modifier update() {
		if(staked) {
			while(block.number > lastUpdate.add(compoundTime)) {
				uint addPrice = basePrice.mul(compoundTime).mul(rewardPerBlock).div(MAG);
				basePrice = basePrice.add(addPrice);
				lastUpdate = lastUpdate.add(compoundTime);
			}
		}

		_;
	}

	function currentPrice() view public returns(uint) {
		require(rewardPerBlock > 0, "Reward Not Set");
		if (!staked) {
			return basePrice;
		}

		uint newPrice = basePrice;
		uint newUpdate = lastUpdate;
		uint addPrice;
		while(block.number > newUpdate.add(compoundTime)) {
			addPrice = basePrice.mul(compoundTime).mul(rewardPerBlock).div(MAG);
			newPrice = newPrice.add(addPrice);
			newUpdate = newUpdate.add(compoundTime);
		}

		addPrice = newPrice.mul(block.number.sub(newUpdate)).mul(rewardPerBlock).div(MAG);
		return newPrice.add(addPrice);
	}

	function setRewardPerBlock(uint _rewardPerBlock, uint _comoundTime) update external onlyOwner {
		rewardPerBlock = _rewardPerBlock;
		compoundTime = _comoundTime;
		emit SetRewardPerBlock(_rewardPerBlock);
	}

	function stake(uint amountInUSP) nonReentrant update external returns (uint amountOutAUSP) {
		uint price = currentPrice();
		usp.safeTransferFrom(msg.sender, address(this), amountInUSP);
		amountOutAUSP = amountInUSP.mul(MAG).div(price);
		ausp.mint(msg.sender, amountOutAUSP);

		if(!staked) {
			lastUpdate = block.number;
			staked = true;
		}

		emit Stake(msg.sender, amountInUSP, amountOutAUSP);
	}
 
	function withdraw(uint amountInAUSP) nonReentrant update external returns (uint amountOutUSP) {
		uint price = currentPrice();
		ausp.burn(msg.sender, amountInAUSP);
		uint totalSupply = ausp.totalSupply();
		amountOutUSP = amountInAUSP.mul(price).div(MAG);

		usp.safeTransfer(msg.sender, amountOutUSP);
		require(totalSupply.mul(price).div(MAG) <= usp.balanceOf(address(this)), "NO ENOUGH REWARD");

		emit Withdraw(msg.sender, amountInAUSP, amountOutUSP);
	}

	function take(uint amount, address to) external onlyOwner {
		uint price = currentPrice();
		uint totalSupply = ausp.totalSupply();
		usp.safeTransfer(to, amount);
		require(totalSupply.mul(price).div(MAG) <= usp.balanceOf(address(this)));
		emit Take(amount, to);
	}
}