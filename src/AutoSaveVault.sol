// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IPayable } from "@reactive/IPayable.sol";
import { AbstractCallback } from "@reactive/AbstractCallback.sol";
import { MockUSDC } from "./MockUSDC.sol";

/// @title AutoSaveVault — "set it and forget it" savings vault (destination chain).
/// @notice Users deposit mUSDC into a per-user escrow. Every deposit emits
///         `DepositReceived`, which the AutoSaveReactive contract on Reactive
///         Network (Lasna) is subscribed to. When the reactive contract sees a
///         qualifying deposit it requests a callback here, and
///         `executeAutoSave` automatically moves the configured savings slice
///         from the user's escrow to their savings wallet — no keeper, no
///         manual step. Users can withdraw the remaining escrow at any time.
///
/// @dev Callback authentication follows the Reactive Omni docs exactly:
///      `onlyServiceProvider` (caller must be this chain's callback proxy)
///      AND `onlyCallbackSender(reactive_)` (injected first argument must be
///      the authorized reactive contract). Keep this contract funded with the
///      destination chain's native token so the proxy can bill callbacks.
contract AutoSaveVault is AbstractCallback {
    MockUSDC public immutable token;
    address public owner;
    address public savingsWallet;

    /// @notice Per-user escrow balance (mUSDC, 6 decimals).
    mapping(address => uint256) public escrowOf;
    /// @notice Lifetime auto-saved amount per user.
    mapping(address => uint256) public savedOf;

    uint256 public totalDeposited;
    uint256 public totalAutoSaved;
    uint256 public autoSaveCount;

    /// @notice Origin event the reactive contract subscribes to.
    /// @dev topic0 = keccak256("DepositReceived(address,uint256,uint256)"),
    ///      topic1 = user, data = abi.encode(amount, newEscrow).
    event DepositReceived(address indexed user, uint256 amount, uint256 newEscrow);
    event Withdrawn(address indexed user, uint256 amount);
    /// @notice Emitted when the reactive callback moves a savings slice.
    event AutoSaved(
        address indexed user, uint256 savedAmount, uint256 remainingEscrow, uint256 originTxHash
    );
    /// @notice Off-chain notifier (Python Telegram bot) listens for this.
    event AlertRaised(address indexed user, uint256 savedAmount, uint256 totalSavedByUser);
    event SavingsWalletUpdated(address indexed oldWallet, address indexed newWallet);

    error NotOwner(address caller);
    error ZeroAmount();
    error InsufficientEscrow(uint256 available, uint256 required);
    error SaveExceedsEscrow(uint256 escrow, uint256 saveAmount);
    error ZeroAddress();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner(msg.sender);
        _;
    }

    /// @param callbackProxy_ Callback proxy on this chain (Base Sepolia:
    ///        0x476F44b11F5C942c58f4c8E3d0300E5710743585).
    /// @param reactiveContract_ AutoSaveReactive address on Reactive Network.
    /// @param token_ mUSDC token address on this chain.
    /// @param savingsWallet_ Where auto-saved slices are sent.
    constructor(
        IPayable callbackProxy_,
        address reactiveContract_,
        MockUSDC token_,
        address savingsWallet_
    ) payable AbstractCallback(callbackProxy_, reactiveContract_) {
        if (savingsWallet_ == address(0)) revert ZeroAddress();
        token = token_;
        savingsWallet = savingsWallet_;
        owner = msg.sender;
    }

    /// @notice Deposit mUSDC into your escrow. Triggers the reactive loop.
    /// @dev Caller must `approve` this vault on the token first.
    function deposit(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        token.transferFrom(msg.sender, address(this), amount);
        escrowOf[msg.sender] += amount;
        totalDeposited += amount;
        emit DepositReceived(msg.sender, amount, escrowOf[msg.sender]);
    }

    /// @notice Withdraw any part of your remaining escrow, any time.
    function withdraw(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        uint256 bal = escrowOf[msg.sender];
        if (bal < amount) revert InsufficientEscrow(bal, amount);
        escrowOf[msg.sender] = bal - amount;
        token.transfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Reactive callback: move `saveAmount` of `user`'s escrow to the
    ///         savings wallet. Only reachable through the Reactive Network
    ///         callback proxy on behalf of the authorized reactive contract.
    /// @param reactive_ Injected by the network (requesting reactive contract).
    /// @param user_ Whose escrow to split.
    /// @param saveAmount_ Slice to move (computed by the reactive contract).
    /// @param originTxHash_ Hash of the origin deposit tx, for auditability.
    function executeAutoSave(
        address reactive_,
        address user_,
        uint256 saveAmount_,
        uint256 originTxHash_
    ) external onlyServiceProvider onlyCallbackSender(reactive_) {
        if (saveAmount_ == 0) revert ZeroAmount();
        uint256 bal = escrowOf[user_];
        if (saveAmount_ > bal) revert SaveExceedsEscrow(bal, saveAmount_);

        escrowOf[user_] = bal - saveAmount_;
        savedOf[user_] += saveAmount_;
        totalAutoSaved += saveAmount_;
        autoSaveCount += 1;

        token.transfer(savingsWallet, saveAmount_);

        emit AutoSaved(user_, saveAmount_, escrowOf[user_], originTxHash_);
        emit AlertRaised(user_, saveAmount_, savedOf[user_]);
    }

    /// @notice Point future auto-saves at a new savings wallet.
    function setSavingsWallet(address newWallet_) external onlyOwner {
        if (newWallet_ == address(0)) revert ZeroAddress();
        emit SavingsWalletUpdated(savingsWallet, newWallet_);
        savingsWallet = newWallet_;
    }

    /// @notice Settle any callback debt from this contract's native balance.
    function coverDebt() external {
        _coverDebt();
    }
}
