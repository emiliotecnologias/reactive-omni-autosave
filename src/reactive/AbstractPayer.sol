// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IPayer } from "./IPayer.sol";
import { IPayable } from "./IPayable.sol";

/// @title AbstractPayer — shared payment plumbing for reactive and callback
///        contracts. The service provider bills this contract; `pay()` is
///        restricted to that provider, and `_coverDebt()` settles any
///        outstanding balance from the contract's own funds.
abstract contract AbstractPayer is IPayer {
    error NotAuthorized(address sender_, address provider_);
    error InsufficientFunds(uint256 required_, uint256 available_);
    error TransferFailed();

    /// @notice The provider allowed to bill this contract (immutable).
    IPayable public immutable _SERVICE_PROVIDER;

    constructor(IPayable serviceProvider_) {
        _SERVICE_PROVIDER = serviceProvider_;
    }

    receive() external payable virtual override {}

    modifier onlyServiceProvider() {
        _requireServiceProvider();
        _;
    }

    function _requireServiceProvider() internal view {
        if (msg.sender != address(_SERVICE_PROVIDER)) {
            revert NotAuthorized(msg.sender, address(_SERVICE_PROVIDER));
        }
    }

    /// @inheritdoc IPayer
    function pay(uint256 amount_) external override onlyServiceProvider {
        _send(payable(msg.sender), amount_);
    }

    /// @notice Settle all outstanding debt from this contract's balance.
    function _coverDebt() internal {
        uint256 owed = _SERVICE_PROVIDER.debt(address(this));
        _send(payable(address(_SERVICE_PROVIDER)), owed);
    }

    function _send(address payable recipient_, uint256 amount_) internal {
        if (address(this).balance < amount_) {
            revert InsufficientFunds(amount_, address(this).balance);
        }
        if (amount_ > 0) {
            (bool ok,) = recipient_.call{ value: amount_ }(new bytes(0));
            if (!ok) revert TransferFailed();
        }
    }
}
