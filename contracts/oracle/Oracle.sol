//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract Oracle is Ownable {

    using SafeMath for uint;
    uint constant MAG = 1e18; 

    event PriceUpdate(string asset, uint price);

    mapping(string => uint) public prices; 

    function setPrice(string[] memory _asset, uint[] memory _price) external onlyOwner {
        require(_asset.length == _price.length, "INVALID PARAMS");
        for(uint i = 0;i < _asset.length;i++) {
            prices[_asset[i]] = _price[i];
            emit PriceUpdate(_asset[i], _price[i]);
        }
    }

    function getPrice(string memory ask) view external returns(uint) {
        require(prices[ask] > 0, "INVALID PRICE");
        return prices[ask];
    }
}
