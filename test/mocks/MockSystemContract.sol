// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { ISystemContract } from "@reactive/ISystemContract.sol";
import { IReactive } from "@reactive/IReactive.sol";

/// @title MockSystemContract — local stand-in for the Reactive system
///        contract (0x8888…8888) + Reactive Signer + callback proxy, used to
///        prove the full origin → react → callback loop in Foundry tests.
/// @dev Tests `vm.etch` this code at the SYSTEM address so contracts that
///      hardcode SYSTEM (AbstractReactive) talk to it. It records every
///      subscription and callback request, and `deliverLastCallback` plays
///      the network's role: it injects the reactive contract's address into
///      the payload's first slot and calls the destination as the proxy.
contract MockSystemContract is ISystemContract {
    struct Subscription {
        uint256 chainId;
        address contractAddr;
        uint256 topic0;
        uint256 topic1;
        uint256 topic2;
        uint256 topic3;
        address subscriber;
    }

    Subscription[] public subscriptions;
    CallbackConfiguration_V_1_0 public lastCallback;
    address public lastCallbackSender;
    uint256 public callbackCount;

    mapping(address => uint256) internal _debt;
    mapping(address => uint256) internal _reserves;

    event Subscribed(address indexed subscriber, uint256 chainId, address contractAddr, uint256 topic0);
    event Unsubscribed(address indexed subscriber, uint256 chainId, address contractAddr, uint256 topic0);
    event CallbackRequested(uint256 indexed chainId, address indexed sender, address indexed recipient);

    // --- ISubscriptionService ---
    function subscribe(
        uint256 chainId_,
        address contract_,
        uint256 topic0_,
        uint256 topic1_,
        uint256 topic2_,
        uint256 topic3_
    ) external override {
        subscriptions.push(
            Subscription(chainId_, contract_, topic0_, topic1_, topic2_, topic3_, msg.sender)
        );
        emit Subscribed(msg.sender, chainId_, contract_, topic0_);
    }

    function unsubscribe(
        uint256 chainId_,
        address contract_,
        uint256 topic0_,
        uint256,
        uint256,
        uint256
    ) external override {
        for (uint256 i = 0; i < subscriptions.length; i++) {
            Subscription storage s = subscriptions[i];
            if (
                s.subscriber == msg.sender && s.chainId == chainId_ && s.contractAddr == contract_
                    && s.topic0 == topic0_
            ) {
                subscriptions[i] = subscriptions[subscriptions.length - 1];
                subscriptions.pop();
                break;
            }
        }
        emit Unsubscribed(msg.sender, chainId_, contract_, topic0_);
    }

    function subscriptionCount() external view returns (uint256) {
        return subscriptions.length;
    }

    // --- ISystemContract callbacks ---
    function requestCallback(CallbackVersion, bytes memory) external override {
        revert("mock: use requestCallbackV_1_0");
    }

    function requestCallbackV_1_0(CallbackConfiguration_V_1_0 memory config_) external override {
        lastCallback = config_;
        lastCallbackSender = msg.sender;
        callbackCount += 1;
        emit CallbackRequested(config_.chainId, msg.sender, config_.recipient);
    }

    /// @notice Simulate Reactive Signer delivering the last requested callback:
    ///         overwrite payload bytes [4..36] with the reactive sender address
    ///         (exactly what the real network does) and call the recipient.
    /// @dev Call this from a prank as the callback proxy in tests, or use
    ///      `deliverLastCallbackAsProxy` which pranks internally is impossible —
    ///      tests prank the proxy address around this call instead. Here we
    ///      simply forward; msg.sender seen by the recipient is this contract,
    ///      so tests etch this mock at BOTH the SYSTEM address and use a
    ///      separate proxy mock for delivery. See AutoSave.t.sol.
    function patchedPayload() external view returns (bytes memory payload) {
        payload = lastCallback.payload;
        address sender = lastCallbackSender;
        // Payload layout: 4-byte selector + 32-byte first arg (address).
        assembly {
            mstore(add(payload, 36), sender)
        }
    }

    // --- IPayable ---
    function debt(address account_) external view override returns (uint256) {
        return _debt[account_];
    }

    function reserves(address account_) external view override returns (uint256) {
        return _reserves[account_];
    }

    function depositTo(address account_) external payable override {
        _reserves[account_] += msg.value;
    }

    function setDebt(address account_, uint256 amount_) external {
        _debt[account_] = amount_;
    }

    receive() external payable {}
}

/// @title MockCallbackProxy — stands in for the destination chain's callback
///        proxy. Vaults are deployed with this contract as `_SERVICE_PROVIDER`;
///        `deliver` calls the vault so `msg.sender == proxy`, mirroring prod.
contract MockCallbackProxy {
    mapping(address => uint256) internal _debt;
    mapping(address => uint256) internal _reserves;

    function debt(address account_) external view returns (uint256) {
        return _debt[account_];
    }

    function reserves(address account_) external view returns (uint256) {
        return _reserves[account_];
    }

    function depositTo(address account_) external payable {
        _reserves[account_] += msg.value;
    }

    function setDebt(address account_, uint256 amount_) external {
        _debt[account_] = amount_;
    }

    /// @notice Deliver a callback payload to `recipient` as the proxy.
    function deliver(address recipient, bytes calldata payload) external returns (bytes memory) {
        (bool ok, bytes memory ret) = recipient.call(payload);
        require(ok, "mock proxy: callback reverted");
        return ret;
    }

    receive() external payable {}
}
