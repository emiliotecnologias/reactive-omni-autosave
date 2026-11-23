// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { ISystemContract } from "./ISystemContract.sol";
import { IReactive } from "./IReactive.sol";
import { AbstractPayer } from "./AbstractPayer.sol";

/// @title AbstractReactive — base for Reactive Omni reactive contracts.
/// @notice Exposes the system contract handle, the topic wildcard, and the
///         `onlySystem` guard for `react()`. Inherit, subscribe in the
///         constructor, implement `react()`, keep the contract funded in REACT.
abstract contract AbstractReactive is AbstractPayer, IReactive {
    /// @notice Reactive system contract (same address on Mainnet + Lasna).
    ISystemContract internal constant SYSTEM =
        ISystemContract(payable(0x8888888888888888888888888888888888888888));

    /// @notice Wildcard value for any subscription topic position.
    uint256 internal constant REACTIVE_IGNORE =
        0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad;

    constructor() AbstractPayer(SYSTEM) {}

    /// @notice Restrict a function to calls from the system contract.
    modifier onlySystem() {
        _requireServiceProvider();
        _;
    }
}
