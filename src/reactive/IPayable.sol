// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title IPayable — payment surface exposed by the Reactive system contract
///        and by each destination chain's callback proxy.
/// @notice Minimal re-implementation of the public Reactive Omni API as
///         documented at https://dev.reactive.network (Reactive Contracts /
///         Callback Contracts / Economy pages). For production deployments,
///         prefer the official library: `forge install Reactive-Network/reactive-lib-omni`.
interface IPayable {
    /// @notice Outstanding debt owed by `account_` to this provider.
    function debt(address account_) external view returns (uint256);

    /// @notice Credit `account_`'s reserves with the sent value.
    function depositTo(address account_) external payable;

    /// @notice Current reserve balance of `account_`.
    function reserves(address account_) external view returns (uint256);
}
