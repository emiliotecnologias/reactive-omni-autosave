// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { TestBase, Vm } from "./TestBase.sol";
import { MockSystemContract, MockCallbackProxy } from "./mocks/MockSystemContract.sol";
import { MockUSDC } from "../src/MockUSDC.sol";
import { AutoSaveVault } from "../src/AutoSaveVault.sol";
import { AutoSaveReactive } from "../src/AutoSaveReactive.sol";
import { IReactive } from "@reactive/IReactive.sol";
import { IPayable } from "@reactive/IPayable.sol";

/// @title AutoSave full-loop tests.
/// @notice Proves the complete Reactive Omni loop locally:
///         1. user deposits mUSDC into AutoSaveVault (origin event),
///         2. the event is packaged as a LogRecord and delivered to
///            AutoSaveReactive.react() by the (mock) system contract,
///         3. the reactive contract requests a callback,
///         4. the (mock) callback proxy delivers it to the vault with the
///            reactive address injected, and the savings slice moves.
///         Plus rule/threshold/pause/auth edge cases.
contract AutoSaveTest is TestBase {
    address internal constant SYSTEM_ADDR = 0x8888888888888888888888888888888888888888;
    uint256 internal constant ORIGIN_CHAIN = 84532; // Base Sepolia
    uint256 internal constant DEST_CHAIN = 84532;

    MockSystemContract internal system;
    MockCallbackProxy internal proxy;
    MockUSDC internal token;
    AutoSaveReactive internal reactive;
    AutoSaveVault internal vault;

    address internal owner = address(0x0A11CE);
    address internal user = address(0xB0B);
    address internal savings = address(0x5AFE);
    address internal attacker = address(0xBAD);

    uint256 internal constant SAVE_BPS = 2000; // 20%
    uint256 internal constant MIN_AMOUNT = 10_000_000; // 10 mUSDC

    function setUp() public {
        // 1) Mock system contract etched at the canonical SYSTEM address.
        MockSystemContract impl = new MockSystemContract();
        vm.etch(SYSTEM_ADDR, address(impl).code);
        system = MockSystemContract(payable(SYSTEM_ADDR));

        proxy = new MockCallbackProxy();
        token = new MockUSDC();

        // 2) Reactive contract first (docs deployment order), funded.
        vm.deal(owner, 10 ether);
        vm.prank(owner);
        reactive = new AutoSaveReactive{ value: 1 ether }(
            ORIGIN_CHAIN, address(0xDEAD), SAVE_BPS, MIN_AMOUNT
        );

        // 3) Vault authorizes the reactive contract; then wire destination.
        vm.prank(owner);
        vault = new AutoSaveVault(IPayable(address(proxy)), address(reactive), token, savings);

        vm.prank(owner);
        reactive.setDestination(DEST_CHAIN, address(vault));

        // Fund vault for callback billing (native token reserves).
        vm.deal(address(vault), 1 ether);

        // User gets test funds.
        vm.prank(user);
        token.mint(1_000_000_000); // 1,000 mUSDC
        vm.prank(user);
        token.approve(address(vault), type(uint256).max);
    }

    // ---------- helpers ----------

    function _deposit(uint256 amount) internal {
        vm.prank(user);
        vault.deposit(amount);
    }

    function _logFor(uint256 amount, uint256 newEscrow)
        internal
        view
        returns (IReactive.LogRecord memory)
    {
        return IReactive.LogRecord({
            chainId: ORIGIN_CHAIN,
            contractAddress: address(vault),
            topic0: reactive.DEPOSIT_TOPIC0(),
            topic1: uint256(uint160(user)),
            topic2: 0,
            topic3: 0,
            data: abi.encode(amount, newEscrow),
            blockNumber: 12345,
            opCode: 2,
            blockHash: 0xB10C,
            txHash: 0x7A11,
            logIndex: 0
        });
    }

    function _react(uint256 amount, uint256 newEscrow) internal {
        IReactive.LogRecord memory log_ = _logFor(amount, newEscrow);
        vm.prank(SYSTEM_ADDR);
        reactive.react(log_);
    }

    function _deliverCallback() internal {
        bytes memory payload = system.patchedPayload();
        proxy.deliver(address(vault), payload);
    }

    // ---------- tests ----------

    function test_SubscriptionRegistered() public view {
        assertEq(system.subscriptionCount(), 1, "one subscription");
        (uint256 chainId, address c, uint256 t0,,,,) = system.subscriptions(0);
        assertEq(chainId, ORIGIN_CHAIN, "origin chain");
        assertEq(c, address(0xDEAD), "origin contract placeholder");
        assertEq(t0, reactive.DEPOSIT_TOPIC0(), "deposit topic0");
    }

    function test_FullLoop_DepositSplitsTwentyPercent() public {
        _deposit(100_000_000); // 100 mUSDC
        assertEq(vault.escrowOf(user), 100_000_000, "escrow after deposit");

        _react(100_000_000, 100_000_000);
        assertEq(system.callbackCount(), 1, "one callback requested");
        assertEq(reactive.callbacksSent(), 1, "reactive counted callback");
        assertEq(reactive.totalSaveRequested(), 20_000_000, "20% requested");

        _deliverCallback();
        assertEq(vault.escrowOf(user), 80_000_000, "escrow keeps 80%");
        assertEq(token.balanceOf(savings), 20_000_000, "savings got 20%");
        assertEq(vault.savedOf(user), 20_000_000, "savedOf tracked");
        assertEq(vault.autoSaveCount(), 1, "autosave counted");
    }

    function test_BelowMinDepositSkipped() public {
        _deposit(5_000_000); // 5 mUSDC < 10 min
        _react(5_000_000, 5_000_000);
        assertEq(system.callbackCount(), 0, "no callback below min");
        assertEq(reactive.depositsSkipped(), 1, "skip counted");
        assertEq(vault.escrowOf(user), 5_000_000, "escrow untouched");
    }

    function test_PausedSkipsAndUnsubscribes() public {
        vm.prank(owner);
        reactive.setPaused(true);
        assertEq(system.subscriptionCount(), 0, "unsubscribed on pause");

        _deposit(100_000_000);
        _react(100_000_000, 100_000_000);
        assertEq(system.callbackCount(), 0, "no callback while paused");

        vm.prank(owner);
        reactive.setPaused(false);
        assertEq(system.subscriptionCount(), 1, "resubscribed on resume");
    }

    function test_ReactRejectsNonSystemCaller() public {
        IReactive.LogRecord memory log_ = _logFor(100_000_000, 100_000_000);
        vm.expectRevert(
            abi.encodeWithSignature(
                "NotAuthorized(address,address)", attacker, SYSTEM_ADDR
            )
        );
        vm.prank(attacker);
        reactive.react(log_);
    }

    function test_CallbackRejectsDirectCaller() public {
        _deposit(100_000_000);
        // Attacker calls the vault directly, forging the reactive address.
        vm.expectRevert(
            abi.encodeWithSignature(
                "NotAuthorized(address,address)", attacker, address(proxy)
            )
        );
        vm.prank(attacker);
        vault.executeAutoSave(address(reactive), user, 20_000_000, 0x7A11);
    }

    function test_CallbackRejectsWrongReactiveSender() public {
        _deposit(100_000_000);
        bytes memory payload = abi.encodeWithSignature(
            "executeAutoSave(address,address,uint256,uint256)",
            attacker, // wrong injected sender
            user,
            20_000_000,
            uint256(0x7A11)
        );
        // Proxy delivers, but onlyCallbackSender must reject.
        (bool ok,) = address(proxy).call(
            abi.encodeWithSignature("deliver(address,bytes)", address(vault), payload)
        );
        assertTrue(!ok, "wrong sender rejected");
        assertEq(vault.escrowOf(user), 100_000_000, "escrow untouched");
    }

    function test_WithdrawRemainingEscrow() public {
        _deposit(100_000_000);
        _react(100_000_000, 100_000_000);
        _deliverCallback();

        vm.prank(user);
        vault.withdraw(80_000_000);
        assertEq(vault.escrowOf(user), 0, "escrow drained");
        assertEq(token.balanceOf(user), 980_000_000, "user balance: 1000-100+80");
    }

    function test_RuleUpdateChangesSplit() public {
        vm.prank(owner);
        reactive.setRule(5000, MIN_AMOUNT); // 50%
        _deposit(100_000_000);
        _react(100_000_000, 100_000_000);
        _deliverCallback();
        assertEq(token.balanceOf(savings), 50_000_000, "50% saved after rule change");
    }

    function test_MultipleDepositsAccumulate() public {
        _deposit(50_000_000);
        _react(50_000_000, 50_000_000);
        _deliverCallback();
        _deposit(50_000_000);
        _react(50_000_000, 90_000_000);
        _deliverCallback();
        assertEq(token.balanceOf(savings), 20_000_000, "2x10 saved");
        assertEq(vault.escrowOf(user), 80_000_000, "escrow 100-20");
        assertEq(reactive.callbacksSent(), 2, "two callbacks");
    }

    function test_WrongTopicIgnoredWithoutRevert() public {
        IReactive.LogRecord memory log_ = _logFor(100_000_000, 100_000_000);
        log_.topic0 = 0x1234;
        vm.prank(SYSTEM_ADDR);
        reactive.react(log_); // must not revert
        assertEq(system.callbackCount(), 0, "no callback for wrong topic");
    }
}
