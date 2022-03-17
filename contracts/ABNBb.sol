// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

interface IInternetBond {
    function mintBonds(address account, uint256 amount) external;

    function burn(address account, uint256 amount) external;

    function pendingBurn(address account) external view returns (uint256);

    function burnAndSetPending(address account, uint256 amount) external;

    function updatePendingBurning(address account, uint256 amount) external;

    function ratio() external view returns (uint256);
}

contract aBNBb is OwnableUpgradeable, ERC20Upgradeable, IInternetBond {
    /**
     * Variables
     */

    address private _operator;
    address private _crossChainBridge;
    address private _binancePool;
    uint256 private _ratio;
    uint256 private _totalStaked;
    uint256 private _totalUnbondedBonds;
    int256 private _lockedShares;

    mapping(address => uint256) private _pendingBurn;
    uint256 private _pendingBurnsTotal;
    uint256 private _collectableFee;

    /**
     * Events
     */

    event RatioUpdated(uint256 newRatio);

    /**
     * Modifiers
     */

    modifier onlyOperator() {
        require(
            msg.sender == owner() || msg.sender == _operator,
            "Operator: not allowed"
        );
        _;
    }

    modifier onlyMinter() {
        require(
            msg.sender == owner() || msg.sender == _crossChainBridge,
            "Minter: not allowed"
        );
        _;
    }

    modifier onlyBondMinter() {
        require(
            msg.sender == owner() || msg.sender == _binancePool,
            "Minter: not allowed"
        );
        _;
    }

    function initialize(address operator) public initializer {
        __Ownable_init();
        __ERC20_init("Ankr BNB Reward Earning Bond", "aBNBb");
        _operator = operator;
        _ratio = 1e18;
    }

    function ratio() public view override returns (uint256) {
        return _ratio;
    }

    /// @dev new_ratio = total_shares/(total_staked + total_reward - unbonds)
    function updateRatio(uint256 totalRewards) public onlyOperator {
        uint256 totalShares = totalSharesSupply();
        uint256 denominator = _totalStaked + totalRewards - _totalUnbondedBonds;
        require(denominator > 0, "denominator <= 0");
        _ratio = (totalShares * 1e18) / denominator;
        emit RatioUpdated(_ratio);
    }

    function repairRatio(uint256 newRatio) public onlyOwner {
        _ratio = newRatio;
        emit RatioUpdated(_ratio);
    }

    function collectableFee() public view returns (uint256) {
        return _collectableFee;
    }

    function repairCollectableFee(uint256 newFee) public onlyOwner {
        _collectableFee = newFee;
    }

    function updateRatioAndFee(uint256 newRatio, uint256 newFee)
        public
        onlyOperator
    {
        // 0.002 * ratio
        uint256 threshold = _ratio / 500;
        require(
            newRatio < _ratio + threshold || newRatio > _ratio - threshold,
            "New ratio should be in limits"
        );
        _ratio = newRatio;
        _collectableFee = newFee;
        emit RatioUpdated(_ratio);
    }

    function totalSupply() public view override returns (uint256) {
        uint256 supply = totalSharesSupply();
        return _sharesToBonds(supply);
    }

    function totalSharesSupply() public view returns (uint256) {
        return super.totalSupply();
    }

    function balanceOf(address account) public view override returns (uint256) {
        uint256 shares = super.balanceOf(account);
        return _sharesToBonds(shares);
    }

    function mintBonds(address account, uint256 amount)
        public
        override
        onlyBondMinter
    {
        _totalStaked += amount;
        uint256 shares = _bondsToShares(amount);
        _mint(account, shares);
    }

    function mint(address account, uint256 shares) public onlyMinter {
        _lockedShares = _lockedShares - int256(shares);
        _mint(account, shares);
    }

    function burn(address account, uint256 amount) public override onlyMinter {
        uint256 shares = _bondsToShares(amount);
        _lockedShares = _lockedShares + int256(shares);
        _burn(account, shares);
    }

    function pendingBurn(address account)
        external
        view
        override
        returns (uint256)
    {
        return _pendingBurn[account];
    }

    function burnAndSetPending(address account, uint256 amount)
        public
        override
        onlyBondMinter
    {
        _pendingBurn[account] = _pendingBurn[account] + amount;
        _pendingBurnsTotal = _pendingBurnsTotal + amount;
        uint256 sharesToBurn = _bondsToShares(amount);
        _totalUnbondedBonds += amount;
        _burn(account, sharesToBurn);
    }

    function updatePendingBurning(address account, uint256 amount)
        public
        override
        onlyBondMinter
    {
        uint256 pendingBurnableAmount = _pendingBurn[account];
        require(pendingBurnableAmount >= amount, "amount is wrong");
        _pendingBurn[account] = pendingBurnableAmount - amount;
        _pendingBurnsTotal = _pendingBurnsTotal - amount;
    }

    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        uint256 shares = _bondsToSharesCeil(amount);
        super.transfer(recipient, shares);
        return true;
    }

    function allowance(address owner, address spender)
        public
        view
        override
        returns (uint256)
    {
        return _sharesToBonds(super.allowance(owner, spender));
    }

    function approve(address spender, uint256 amount)
        public
        override
        returns (bool)
    {
        uint256 shares = _bondsToSharesCeil(amount);
        super.approve(spender, shares);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        uint256 shares = _bondsToSharesCeil(amount);
        super.transferFrom(sender, recipient, shares);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue)
        public
        override
        returns (bool)
    {
        uint256 shares = _bondsToShares(addedValue);
        super.increaseAllowance(spender, shares);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        override
        returns (bool)
    {
        uint256 shares = _bondsToShares(subtractedValue);
        super.decreaseAllowance(spender, shares);
        return true;
    }

    function _bondsToShares(uint256 amount) internal view returns (uint256) {
        return multiplyAndDivide(amount, _ratio, 1e18);
    }

    function _bondsToSharesCeil(uint256 amount)
        internal
        view
        returns (uint256)
    {
        return multiplyAndDivideCeil(amount, _ratio, 1e18);
    }

    function _sharesToBonds(uint256 amount) internal view returns (uint256) {
        return multiplyAndDivide(amount, 1e18, _ratio);
    }

    function _sharesToBondsCeil(uint256 amount)
        internal
        view
        returns (uint256)
    {
        return multiplyAndDivideCeil(amount, 1e18, _ratio);
    }

    function totalStaked() public view returns (uint256) {
        return _totalStaked;
    }

    function totalUnbondedBonds() public view returns (uint256) {
        return _totalUnbondedBonds;
    }

    function changeOperator(address operator) public onlyOwner {
        _operator = operator;
    }

    function changeBinancePool(address binancePool) public onlyOwner {
        _binancePool = binancePool;
    }

    function changeCrossChainBridge(address crossChainBridge) public onlyOwner {
        _crossChainBridge = crossChainBridge;
    }

    function lockedSupply() public view returns (int256) {
        return _lockedShares;
    }

    function multiplyAndDivide(
        uint256 a,
        uint256 b,
        uint256 c
    ) internal pure returns (uint256) {
        return (a / c) * b + ((a % c) * b) / c;
    }

    function multiplyAndDivideCeil(
        uint256 a,
        uint256 b,
        uint256 c
    ) internal pure returns (uint256) {
        return (a / c) * b + ((a % c) * b + (c - 1)) / c;
    }
}
