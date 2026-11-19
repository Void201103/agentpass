// AgentPass frontend configuration.
// Live on BNB Smart Chain mainnet since 2026-11-19 (deployed via CREATE2 factory).
const CONFIG = {
  // BNB Smart Chain (chain id 56)
  chainId: 56,
  chainName: "BNB Smart Chain",
  chainHex: "0x38",
  rpcUrl: "https://bsc-dataseed.binance.org",
  explorer: "https://bscscan.com",
  agentPassAddress: "0xB097e4968BD615748162d999a01eADdcec853055",
  agentIdRegistryAddress: "0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F", // SPACE ID Agent ID (mainnet)

  // BNB Chain Testnet (chain id 97) — kept for reference:
  // chainId: 97,
  // chainName: "BNB Smart Chain Testnet",
  // chainHex: "0x61",
  // rpcUrl: "https://bsc-testnet.publicnode.com",
  // explorer: "https://testnet.bscscan.com",
  // agentPassAddress: "0x0000000000000000000000000000000000000000", // TODO: testnet AgentPass address
  // agentIdRegistryAddress: "0x0000000000000000000000000000000000000000", // TODO: testnet mock registry address
};
