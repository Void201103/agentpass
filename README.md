# AgentPass

Soulbound attendance badges (POAP-style) for Agent ID holders at community events.

Built for the **Binance Agent ID Hackathon** (submission period 18 Nov – 9 Dec 2026).
Organizers create events; holders of an Agent ID claim one badge per event — free,
gas only. Badges are soulbound ERC-721 tokens: they cannot be transferred or sold.

- Project site (GitHub Pages): https://void201103.github.io/agentpass/
- Contract: `src/AgentPass.sol` (single contract: event registry + ERC-721 badge)
- Tests: `test/AgentPass.t.sol` — 22 tests, all passing (`forge test`)
- Frontend: `frontend/` — static HTML/JS, no build step

## How Agent ID is used

AgentPass checks Agent ID ownership **on-chain** against the SPACE ID Agent ID
registry (ERC-721, non-transferable) on BNB Chain:

| Address | Value |
|---|---|
| Agent ID registry (BNB Chain mainnet) | `0x60b9262456de011f7d15a54cdd8c48baaa8b022f` |
| AgentPass contract (testnet) | TBD after testnet deploy |
| AgentPass contract (mainnet) | TBD after mainnet deploy |

- **Creating an event** requires holding an Agent ID (`balanceOf(caller) > 0`).
- **Claiming a badge** requires holding an Agent ID, being inside the event's
  claim window, never having claimed that event, and remaining supply.
- The frontend also reads the registry to show whether the connected wallet
  holds an Agent ID before offering the claim button.

## How it works

1. An organizer (any Agent ID holder) creates an event: name, description,
   claim window (start/end), max supply, optional metadata URI.
2. Agent ID holders connect their own wallet (MetaMask/Rabby) and claim one
   badge per event while the window is open and supply remains.
3. The badge is a soulbound ERC-721: every transfer between two non-zero
   addresses reverts, and `approve` / `setApprovalForAll` revert too.
4. Claiming is free (gas only). There is no payment, no token sale, and no
   promised return of any kind.

## Owner permissions (minimal, documented)

The contract owner is an **explicit constructor parameter** (not `msg.sender`),
so the contract can be deployed through a CREATE2 factory without the factory
becoming the owner. On mainnet the owner is 0xvoid.ai
(`0x4DEdeC3f5a3bf02b3525AAa15c3374af74cC4837`). The owner can only do two things:

| Function | Effect |
|---|---|
| `setBaseURI(string)` | Changes the base URI used for `tokenURI` when an event has no custom `metadataURI`. Does not affect badges whose event sets its own metadata URI. |
| `setEventCreationPaused(bool)` | Pauses/unpauses creation of *new* events (emergency spam brake). Existing events and claims are unaffected. |

The owner **cannot**: mint badges to anyone (badges can only be claimed by the
holder themselves), move user funds (the contract never holds user funds),
change event windows or supplies, pause claims, or transfer badges.
There is no proxy, no upgrade path, and no fee collector.

## Hackathon red-line compliance

- No QR-code / pairing-code login anywhere: users connect their own injected
  wallet and confirm every transaction themselves in that wallet.
- No user login sessions are stored anywhere (no backend at all — the
  frontend is static and reads the chain directly).
- No transaction-confirmation bypass: every state-changing action is a normal
  wallet transaction the user reviews and confirms.
- No unauthorized asset transfers: the contract has no function that moves
  user assets, collects approvals, or schedules transfers.
- Contract is open-source (this repo), with owner permissions documented
  above.
- No use of the Binance or BNB brand in the project name, token name,
  or domain.
- No seed phrases, private keys, API secrets, or pairing codes are collected.
- No returns are promised anywhere in the product or docs.
- No trading functionality, so no trading risk warning is applicable.
- Agent ID is used as an access credential for the holder themselves, never
  as a tool to look up other people's wallets by name.
- No fake volume or mass accounts: one badge per Agent ID per event, enforced
  on-chain.

## Run the frontend

The frontend is static. Serve the `frontend/` folder (e.g. `python3 -m http.server`
inside it) or open `frontend/index.html` via GitHub Pages. It loads ethers.js
from a CDN and talks to the public BSC RPC. Edit `frontend/config.js` to point
at the deployed contract (testnet by default; mainnet values are commented
inside the file).

## Develop

```bash
forge build
forge test
```

## Deploy

Testnet (uses a mock Agent ID registry, since testnet has none):

```bash
export PRIVATE_KEY=<deployer key>   # never commit this
forge script script/DeployTestnet.s.sol --rpc-url https://bsc-testnet.publicnode.com --broadcast
```

Mainnet (real Agent ID registry, no mock):

```bash
export PRIVATE_KEY=<deployer key>
export BASE_URI=https://void201103.github.io/agentpass/api/
forge script script/Deploy.s.sol --rpc-url https://bsc-dataseed.binance.org --broadcast
```

## Verify source

Sourcify (free, no API key):

```bash
forge verify-contract --verifier sourcify --chain 56 <address> src/AgentPass.sol:AgentPass
```

BscScan (needs a free API key from basescan.org/myapikey):

```bash
export ETHERSCAN_API_KEY=<key>
forge verify-contract --chain 56 <address> src/AgentPass.sol:AgentPass
```

## Security notes

- Badges are soulbound and free. The contract holds no funds and has no
  withdrawal function.
- Event metadata URIs are set by the event organizer at creation time and
  cannot be changed afterwards — check them before claiming.
- This project is an independent community project and is not affiliated
  with, or endorsed by, Binance.
