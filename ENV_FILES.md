# Environment Files Guide

This repo contains multiple local `.env*` files for different workflows.

## Active Profiles

| File | Purpose | Used By |
|---|---|---|
| `.env` | Base deploy/policy config for active Foundry scripts | `script/DeployV30Full.s.sol`, `script/DeployDeFiGuard.s.sol`, policy scripts |
| `.env.mainnet` | Mainnet-oriented address/RPC profile | Mainnet deployment/ops runs |
| `.env.demo-agent` | Mint + list demo/template agent | `script/run-list-demo.ps1`, `script/ListDemoAgent.s.sol` |
| `.env.update-pack` | Update an existing agent pack pointer | `script/run-update-pack.ps1`, `script/UpdateAgentPack.s.sol` |

## Protected Backup

| File | Purpose |
|---|---|
| `.env.bak` | Local backup of test environment values. Keep this file. |

## Legacy

| File | Status |
|---|---|
| `.env.demo.legacy` | Deprecated old demo env. Replaced by `.env.demo-agent`. |
| `.env.llm-agent-1.legacy` | Archived LLM demo profile #1. |
| `.env.llm-agent-2.legacy` | Archived LLM demo profile #2. |

## Minimal Set Recommendation

If you want a cleaner local setup, keep only:

1. `.env`
2. `.env.demo-agent`
3. `.env.update-pack`
4. `.env.mainnet` (only if you run mainnet)
5. `.env.bak` (backup)

## Safety

- Never commit real private keys.
- Keep all `.env*` local-only.
- Rotate keys immediately if a key is exposed.
