// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title ISubscriptionService — event subscriptions on the Reactive system contract.
/// @notice A subscription is six criteria: origin chain, origin contract, and
///         topics 0-3. Chain 0 / contract address(0) / REACTIVE_IGNORE act as
///         wildcards; at least one criterion must be specific.
interface ISubscriptionService {
    function subscribe(
        uint256 chainId_,
        address contract_,
        uint256 topic0_,
        uint256 topic1_,
        uint256 topic2_,
        uint256 topic3_
    ) external;

    function unsubscribe(
        uint256 chainId_,
        address contract_,
        uint256 topic0_,
        uint256 topic1_,
        uint256 topic2_,
        uint256 topic3_
    ) external;
}
