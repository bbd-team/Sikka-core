// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

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

contract Earn is Ownable {
	using SafeMath for uint;
	AUSP public ausp;
	uint public rewardPerBlock;
	uint public lastUpdate;
	ERC20 public usp;
	uint public totalStake;
	uint public price = 1e18;
	bool public staked = false;

	uint constant MAG = 1e18;
	using SafeERC20 for ERC20;

	event SetRewardPerBlock(uint rewardPerBlock);
	event Stake(uint amountInUSP, uint amountOutAUSP);
	event Withdraw(uint amountInAUSP, uint amountOutUSP);

	constructor(ERC20 _usp) {
		ausp = new AUSP("AUSP", "AUSP");
		usp = _usp;
	}

	modifier update() {
		if(staked) {
			uint addPrice = price.mul(block.number.sub(lastUpdate)).mul(rewardPerBlock).div(MAG);
			price = price.add(addPrice);
		}

		lastUpdate = block.number;
		_;
	}

	function currentPrice() view external returns(uint){
		uint addPrice = price.mul(block.number.sub(lastUpdate)).mul(rewardPerBlock).div(MAG);
		return price.add(addPrice);
	}

	function setRewardPerBlock(uint _rewardPerBlock) update external onlyOwner {
		rewardPerBlock = _rewardPerBlock;
		emit SetRewardPerBlock(_rewardPerBlock);
	}

	function stake(uint amountInUSP) update external returns (uint amountOutAUSP) {
		usp.safeTransferFrom(msg.sender, address(this), amountInUSP);
		amountOutAUSP = amountInUSP.mul(MAG).div(price);
		ausp.mint(msg.sender, amountOutAUSP);
		staked = true;

		emit Stake(amountInUSP, amountOutAUSP);
	}
 
	function withdraw(uint amountInAUSP) update external returns (uint amountOutUSP) {
		ausp.burn(msg.sender, amountInAUSP);
		uint totalSupply = ausp.totalSupply();
		amountOutUSP = amountInAUSP.mul(price).div(MAG);

		usp.safeTransfer(msg.sender, amountOutUSP);
		require(totalSupply.mul(price).div(MAG) <= usp.balanceOf(address(this)), "NO ENOUGH REWARD");

		emit Withdraw(amountInAUSP, amountOutUSP);
	}

	function take(uint amount) external onlyOwner {
		uint totalSupply = ausp.totalSupply();
		usp.safeTransfer(msg.sender, amount);
		require(totalSupply.mul(price).div(MAG) <= usp.balanceOf(address(this)));
	}
}