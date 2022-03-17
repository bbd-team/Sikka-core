// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface ISKU {
    function mint(address _to, uint256 _amount) external;

    function burn(address _from, uint256 _amount) external;
}