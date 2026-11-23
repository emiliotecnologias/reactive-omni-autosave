// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IPayable } from "./IPayable.sol";
import { AbstractPayer } from "./AbstractPayer.sol";

/// @title AbstractCallback — base for destination-chain callback contracts.
/// @notice Authenticate every callback with BOTH guards:
///         `onlyServiceProvider` (caller is the chain's callback proxy) and
///         `onlyCallbackSender(reactive_)` (the address injected into the
///         payload's first slot is the reactive contract you authorized).
///         Fund the contract in the destination chain's native token.
abstract contract AbstractCallback is AbstractPayer {
    error CallbackNotAuthorized(address sender_, address expectedSender_);

    /// @notice The reactive contract authorized to trigger callbacks (immutable).
    address public immutable _CALLBACK_SENDER;

    /// @param callbackProxy_ Destination chain's callback proxy (see docs:
    ///        Origins & Destinations table).
    /// @param callbackSender_ Reactive contract allowed to call back here.
    constructor(IPayable callbackProxy_, address callbackSender_) AbstractPayer(callbackProxy_) {
        _CALLBACK_SENDER = callbackSender_;
    }

    modifier onlyCallbackSender(address callbackSender_) {
        if (callbackSender_ != _CALLBACK_SENDER) {
            revert CallbackNotAuthorized(callbackSender_, _CALLBACK_SENDER);
        }
        _;
    }
}
