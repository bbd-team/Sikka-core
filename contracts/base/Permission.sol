// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract Permission is Ownable {
	using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _permissions;

    event AddPermission(address indexed permission);
    event DelPermission(address indexed permission);

    function addPermission(address _addPermission) public onlyOwner returns (bool) {
        require(_addPermission != address(0), "Multiple: _addPermission is the zero address");
        emit AddPermission(_addPermission);
        return EnumerableSet.add(_permissions, _addPermission);
    }

    function delPermission(address _delPermission) public onlyOwner returns (bool) {
        require(_delPermission != address(0), "Multiple: _delPermission is the zero address");
        emit DelPermission(_delPermission);
        return EnumerableSet.remove(_permissions, _delPermission);
    }

    function getPermissionLength() public view returns (uint256) {
        return EnumerableSet.length(_permissions);
    }

    function isPermission(address account) public view returns (bool) {
        return EnumerableSet.contains(_permissions, account);
    }

    function getPermission(uint256 _index) public view onlyOwner returns (address){
        require(_index <= getPermissionLength() - 1, "Multiple: index out of bounds");
        return EnumerableSet.at(_permissions, _index);
    }

    // modifier for mint function
    modifier onlyPermission() {
        require(isPermission(msg.sender), "caller is not the permission");
        _;
    }
}