// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title IPayer — implemented by contracts that pay a Reactive service
///        provider (system contract or callback proxy) for execution.
interface IPayer {
    /// @notice Called by the service provider to collect `amount_` of debt.
    function pay(uint256 amount_) external;

    /// @notice Contracts must accept native-token top-ups.
    receive() external payable;
}
