# Script Guide

This file documents active scripts under `repos/shll/script`.

## Active Scripts

1. `DeployV32PostAudit.s.sol` **(PRIMARY - use this)**
Full redeployment after EVMBench security audit. Deploys 10 contracts (9 + DeFiGuardPolicy merged in) + LLM template in 2 phases. Includes all post-audit security fixes (10H/4M/1L).

2. `ListDemoAgent.s.sol`
Mint one configurable demo/template agent and create listing.

3. `UpdateAgentPack.s.sol`
Update `vaultURI` and `vaultHash` for an existing token.

4. `MintTestAgents.s.sol`
Mint and list test agents for local/testnet validation.

5. `RegisterTemplate.s.sol`
Register template metadata/policies for existing token flow.

6. `RegisterLLMTemplate.s.sol`
Register LLM template policy bundle.

7. `MintLLMAgent.s.sol`
Mint an LLM-style agent profile for tests.

8. `hashPack.ts`
Canonicalize manifest and generate SHA256 for `vaultHash`.

9. `run-list-demo.ps1`
Load env file and run `ListDemoAgent.s.sol`.

10. `run-update-pack.ps1`
Load env file and run `UpdateAgentPack.s.sol`.

11. `BackfillLegacySubscription.s.sol`
Backfill one legacy instance subscription record for strict subscription mode migration.

12. `run-backfill-legacy.ps1`
Batch backfill helper using CSV rows (one row = one instance subscription record).

## Env Templates

1. `script/demo-agent.env.example`
Copy to `repos/shll/.env.demo-agent`.

2. `script/update-pack.env.example`
Copy to `repos/shll/.env.update-pack`.

3. `repos/shll/ENV_FILES.md`
Single source of truth for env profile usage.

## Recommended Commands

### Full Deploy V3.2 (Post-Audit)

Foundry auto-loads `.env` from the project root. Use `.env` for testnet, `.env.mainnet` for mainnet.

```powershell
cd repos/shll

# BSC Testnet (uses .env by default)
forge script script/DeployV32PostAudit.s.sol:DeployV32PostAudit --rpc-url $env:RPC_URL --broadcast --gas-price 5000000000 -vvv

# BSC Mainnet (copy .env.mainnet -> .env first, restore after)
Copy-Item .env .env.bak; Copy-Item .env.mainnet .env
forge script script/DeployV32PostAudit.s.sol:DeployV32PostAudit --account deployer --rpc-url $env:RPC_URL --broadcast --gas-price 3000000000 --verify --etherscan-api-key $env:ETHERSCAN_API_KEY -vvv
Copy-Item .env.bak .env
```

**Required env vars**: `ROUTER_ADDRESS`, `USDT_ADDRESS`, `WBNB_ADDRESS`
**Auth**: testnet uses `PRIVATE_KEY` in `.env`; mainnet uses `--account deployer` (keystore)

### List Demo Agent

```powershell
powershell -ExecutionPolicy Bypass -File .\repos\shll\script\run-list-demo.ps1 -EnvFile .\repos\shll\.env.demo-agent -Broadcast
```

### Update Pack Pointer

```powershell
powershell -ExecutionPolicy Bypass -File .\repos\shll\script\run-update-pack.ps1 -EnvFile .\repos\shll\.env.update-pack -Broadcast
```

### Generate Pack Hash

```powershell
cd repos/shll; node --experimental-strip-types script/hashPack.ts ..\shll-packs-private\base_trader\manifest.json
```

### Backfill Legacy Subscription (Strict Mode Migration)

```powershell
cd repos/shll
forge script script/BackfillLegacySubscription.s.sol:BackfillLegacySubscription --rpc-url $env:RPC_URL --broadcast -vvv
```

**Required env vars**: `SUBSCRIPTION_MANAGER`, `AGENT_NFA`, `INSTANCE_ID`, `LISTING_ID`, `PRICE_PER_PERIOD`, `PERIOD_DAYS`, `GRACE_DAYS`, `CURRENT_PERIOD_END`  
**Optional**: `SUBSCRIBER` (defaults to current owner), `DRY_RUN=true`  
**Precondition**: `SubscriptionManager.pause()` has been executed before backfill.

### Batch Backfill (CSV)

```powershell
cd repos/shll
powershell -ExecutionPolicy Bypass -File .\script\run-backfill-legacy.ps1 -CsvPath .\script\legacy-backfill.csv -RpcUrl $env:RPC_URL
powershell -ExecutionPolicy Bypass -File .\script\run-backfill-legacy.ps1 -CsvPath .\script\legacy-backfill.csv -RpcUrl $env:RPC_URL -Broadcast
```

CSV header:
`instanceId,listingId,pricePerPeriod,periodDays,graceDays,currentPeriodEnd,subscriber`

## Legacy Scripts

Historical one-off scripts were moved to `repos/shll/legacy/scripts` to keep the main flow clean.

Legacy deployment scripts (superseded by V3.2):
- `DeployV30Full.s.sol` — V3.0 deployment (pre-audit, 9 contracts)
- `DeployDeFiGuard.s.sol` — Standalone DeFiGuard deploy (now merged into V3.2)
