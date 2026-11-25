# AutoSave Sentinel — Testnet Deploy Runbook (resume here)

Status 2026-11-25 ~02:50 UTC: **BLOCKED on faucet funds.** Everything else is ready.
`forge test` passes 11/11. Both RPCs reachable (Base Sepolia `https://sepolia.base.org`,
Lasna `https://lasna-rpc.rnk.dev/`). No contracts deployed, no txs sent, $0 spent.

## Fresh test-only wallet (created 2026-11-25, never used, no funds yet)

- Address: `0x5c2808b769E4B9e8C2C0C72f759ddaB2Bd3DF737`
- Private key: ONLY in `.testnet-wallet.txt` in this dir (mode 600, git-ignored).
  Never paste it anywhere, never commit it, never reuse it for mainnet.
- Balances confirmed 0: Base Sepolia ETH = 0, Lasna REACT = 0.

## Step 0 — Fund it (needs a live browser + captcha; a subagent cannot do this)

Claim Base Sepolia ETH for the address above, aiming for **~0.2 ETH total**:
- QuickNode faucet https://faucet.quicknode.com (no account, no mainnet history; bot check) — best for a brand-new wallet.
- Chainlink faucet https://faucets.chain.link/base-sepolia (0.5 ETH drip, wallet connect).
- Alchemy https://www.alchemy.com/faucets/base-sepolia (0.1 ETH/24h, but requires ≥0.001 ETH mainnet history — fresh wallet FAILS this, skip unless funded).
- NOT tried / needs sign-in, do not create accounts with personal data: Coinbase CDP faucet, Superchain faucet, Google Cloud faucet.

Then convert some Base Sepolia ETH to Lasna REACT (Reactive docs, "Get Testnet REACT",
rate 1 ETH → 100 lREACT, max 5 ETH/tx — never send more than 5 ETH):

```bash
cast send 0x2afaFD298b23b62760711756088F75B7409f5967 \
  --rpc-url https://sepolia.base.org --private-key $PRIVATE_KEY \
  "request(address)" 0x5c2808b769E4B9e8C2C0C72f759ddaB2Bd3DF737 --value 0.1ether
# → ~10 lREACT on Lasna. DeployReactive funds the contract with 0.1 REACT by default.
```

Verify: `cast balance <addr> --rpc-url https://sepolia.base.org` and
`cast balance <addr> --rpc-url https://lasna-rpc.rnk.dev/`.

## Step 1 — Deploy reactive on Lasna

```bash
export PATH="$HOME/.foundry/bin:$PATH"
cd ~/workspace/emilio-tecnologias/bounties/reactive-omni
export PRIVATE_KEY=$(grep -o '0x[0-9a-f]*' .testnet-wallet.txt | tail -1)  # file is one line: "<address>\t<private-key>"
export SAVINGS_WALLET=0x5c2808b769E4B9e8C2C0C72f759ddaB2Bd3DF737  # deployer = savings wallet for the demo
ORIGIN_VAULT=0x0000000000000000000000000000000000000000 \
  forge script script/Deploy.s.sol:DeployReactive --rpc-url lasna --broadcast
# → note REACTIVE_ADDR
```

## Step 2 — Deploy token + vault on Base Sepolia

```bash
REACTIVE_ADDR=0x… forge script script/Deploy.s.sol:DeployVault \
  --rpc-url base_sepolia --broadcast
# → note TOKEN_ADDR + VAULT_ADDR
```

## Step 3 — Wire destination on Lasna

```bash
REACTIVE_ADDR=0x… VAULT_ADDR=0x… \
  forge script script/Deploy.s.sol:WireDestination --rpc-url lasna --broadcast
```

## Step 4 — Trigger the loop (mint + deposit 100 mUSDC)

```bash
TOKEN_ADDR=0x… VAULT_ADDR=0x… \
  forge script script/Deploy.s.sol:TriggerDeposit --rpc-url base_sepolia --broadcast
```

## Step 5 — Collect evidence + finish

- Deposit tx (Base Sepolia): `cast receipt <tx> --rpc-url https://sepolia.base.org`
- Reactive tx / CallbackRequest (Lasna): https://lasna.reactscan.net/ (explorer per Reactive docs is `https://lasna.reactscan.net/`)
- Callback tx with `AutoSaved` event (Base Sepolia): check `cast logs --from-block <n> --address <VAULT> --rpc-url https://sepolia.base.org`, or Basescan Sepolia.
- Fill the PENDING fields in SUBMISSION.md + the README "Honest status" line, commit + push
  (git identity: `emiliotecnologias` / `emiliotecnologias@users.noreply.github.com`).
- Verify: `cast call <VAULT> "escrowOf(address)(uint256)" <deployer> --rpc-url https://sepolia.base.org`
  should show 80,000,000 (80 mUSDC left after 20% auto-save) and savings wallet holds 20 mUSDC.

## Faucet attempts already made (2026-11-25, all failed without a browser)

- Alchemy Base Sepolia / Sepolia: fresh wallet fails the ≥0.001 ETH mainnet-history check; also a web form + captcha.
- QuickNode faucet API via curl: endpoint returned the HTML page; its claim flow needs a browser bot-check.
- pk910 Sepolia PoW faucet API (`/api/startSession`): `INVALID_CAPTCHA — captcha token missing`.
- Chainlink / Chainstack / Superchain / CDP faucets: web form / wallet-connect / sign-in only.
