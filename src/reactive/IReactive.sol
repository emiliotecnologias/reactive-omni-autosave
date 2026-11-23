// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IPayer } from "./IPayer.sol";

/// @title IReactive — entry point the Reactive system contract calls when a
///        subscribed log appears on an origin chain.
interface IReactive is IPayer {
    /// @notice Normalized representation of an EVM log record.
    /// @dev `data` holds ABI-encoded non-indexed params; `opCode` is the
    ///      number of topics the original log carried (LOG0..LOG4).
    struct LogRecord {
        uint256 chainId;
        address contractAddress;
        uint256 topic0;
        uint256 topic1;
        uint256 topic2;
        uint256 topic3;
        bytes data;
        uint256 blockNumber;
        uint256 opCode;
        uint256 blockHash;
        uint256 txHash;
        uint256 logIndex;
    }

    /// @notice Legacy callback event (deprecated; kept for interface parity).
    event Callback(
        uint256 indexed chainId_,
        address indexed contract_,
        uint64 indexed gasLimit_,
        bytes payload_
    );

    /// @notice Handle a matched log. Must authenticate the caller (onlySystem).
    function react(LogRecord calldata log_) external;
}
