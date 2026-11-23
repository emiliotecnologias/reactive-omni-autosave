// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IPayable } from "./IPayable.sol";
import { ISubscriptionService } from "./ISubscriptionService.sol";

/// @title ISystemContract — Reactive Network system contract (Omni).
/// @notice Deployed at 0x8888888888888888888888888888888888888888 on both
///         Reactive Mainnet (1597) and Lasna testnet (5318007).
interface ISystemContract is IPayable, ISubscriptionService {
    enum CallbackVersion {
        V_1_0
    }

    /// @notice V1.0 callback configuration.
    /// @dev The first 160 bits of `payload` are overwritten by the network
    ///      with the requesting reactive contract's address, so the payload
    ///      MUST start with an `address` argument (pass address(0)).
    struct CallbackConfiguration_V_1_0 {
        uint256 chainId;
        address recipient;
        uint64 gasLimit;
        bytes payload;
    }

    function requestCallback(CallbackVersion version_, bytes memory config_) external;

    function requestCallbackV_1_0(CallbackConfiguration_V_1_0 memory config_) external;
}
