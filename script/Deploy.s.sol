// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { MockUSDC } from "../src/MockUSDC.sol";
import { AutoSaveVault } from "../src/AutoSaveVault.sol";
import { AutoSaveReactive } from "../src/AutoSaveReactive.sol";
import { IPayable } from "@reactive/IPayable.sol";

/// @notice Minimal script cheatcodes (no forge-std dependency).
interface VmScript {
    function envUint(string calldata name) external view returns (uint256);
    function envAddress(string calldata name) external view returns (address);
    function envOr(string calldata name, uint256 defaultValue) external view returns (uint256);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

/// @title Deployment scripts for AutoSave Sentinel (testnets only).
/// @notice ORDER MATTERS (Reactive docs): deploy the reactive contract on
///         Lasna first, then the vault on Base Sepolia with the reactive
///         address, then `setDestination` on the reactive contract.
///
///         Step 1 (Lasna):  forge script script/Deploy.s.sol:DeployReactive \
///           --rpc-url lasna --broadcast
///         Step 2 (Base Sepolia): forge script script/Deploy.s.sol:DeployVault \
///           --rpc-url base_sepolia --broadcast
///         Step 3 (Lasna):  forge script script/Deploy.s.sol:WireDestination \
///           --rpc-url lasna --broadcast
///
///         Required env: PRIVATE_KEY (testnet-only dev key),
///         ORIGIN_VAULT (step 1: vault address if known, else 0x0…0 placeholder
///         is NOT usable — deploy vault first if you need the exact address;
///         recommended flow: DeployVault needs REACTIVE_ADDR, so run step 1
///         with ORIGIN_VAULT set to the predicted vault address OR deploy a
///         first vault, then redeploy reactive pointing at it. See README
///         "Deployment" for the exact two-pass procedure.)
///         REACTIVE_ADDR (step 2), SAVINGS_WALLET (step 2), VAULT_ADDR (step 3).
abstract contract ScriptBase {
    VmScript internal constant vm =
        VmScript(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 internal constant BASE_SEPOLIA = 84532;
    // Base Sepolia callback proxy (Reactive docs: Origins & Destinations).
    address internal constant BASE_SEPOLIA_PROXY = 0x476F44b11F5C942c58f4c8E3d0300E5710743585;
}

/// @notice Step 1 — deploy AutoSaveReactive on Lasna (chain 5318007).
/// @dev Fund with testnet REACT at deploy (value) so react() can run.
///      Get testnet REACT by sending Sepolia/Base-Sepolia ETH to the faucet
///      contracts listed in the README.
contract DeployReactive is ScriptBase {
    function run() external returns (AutoSaveReactive reactive) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address originVault = vm.envAddress("ORIGIN_VAULT");
        uint256 saveBps = vm.envOr("SAVE_BPS", 2000);
        uint256 minAmount = vm.envOr("MIN_AMOUNT", 10_000_000);
        uint256 fund = vm.envOr("REACTIVE_FUND_WEI", 0.1 ether);

        vm.startBroadcast(pk);
        reactive = new AutoSaveReactive{ value: fund }(
            BASE_SEPOLIA, originVault, saveBps, minAmount
        );
        vm.stopBroadcast();
    }
}

/// @notice Step 2 — deploy MockUSDC + AutoSaveVault on Base Sepolia.
contract DeployVault is ScriptBase {
    function run() external returns (MockUSDC token, AutoSaveVault vault) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address reactiveAddr = vm.envAddress("REACTIVE_ADDR");
        address savingsWallet = vm.envAddress("SAVINGS_WALLET");
        uint256 fund = vm.envOr("VAULT_FUND_WEI", 0.01 ether);

        vm.startBroadcast(pk);
        token = new MockUSDC();
        vault = new AutoSaveVault{ value: fund }(
            IPayable(BASE_SEPOLIA_PROXY), reactiveAddr, token, savingsWallet
        );
        vm.stopBroadcast();
    }
}

/// @notice Step 3 — point the reactive contract at the deployed vault.
contract WireDestination is ScriptBase {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address reactiveAddr = vm.envAddress("REACTIVE_ADDR");
        address vaultAddr = vm.envAddress("VAULT_ADDR");

        vm.startBroadcast(pk);
        AutoSaveReactive(payable(reactiveAddr)).setDestination(BASE_SEPOLIA, vaultAddr);
        vm.stopBroadcast();
    }
}

/// @notice Step 4 — end-to-end smoke test: mint + deposit (triggers the loop).
contract TriggerDeposit is ScriptBase {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address tokenAddr = vm.envAddress("TOKEN_ADDR");
        address vaultAddr = vm.envAddress("VAULT_ADDR");
        uint256 amount = vm.envOr("DEPOSIT_AMOUNT", 100_000_000);

        vm.startBroadcast(pk);
        MockUSDC(tokenAddr).mint(amount);
        MockUSDC(tokenAddr).approve(vaultAddr, amount);
        AutoSaveVault(payable(vaultAddr)).deposit(amount);
        vm.stopBroadcast();
    }
}
