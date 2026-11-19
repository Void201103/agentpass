// AgentPass frontend configuration.
// Fill in the contract addresses after deploy. Testnet first; mainnet when deployed.
const CONFIG = {
  // BNB Chain Testnet (chain id 97)
  chainId: 97,
  chainName: "BNB Smart Chain Testnet",
  chainHex: "0x61",
  rpcUrl: "https://bsc-testnet.publicnode.com",
  explorer: "https://testnet.bscscan.com",
  agentPassAddress: "0x0000000000000000000000000000000000000000", // TODO: testnet AgentPass address
  agentIdRegistryAddress: "0x0000000000000000000000000000000000000000", // TODO: testnet mock registry address

  // Mainnet (chain id 56) — switch these in after the mainnet deploy:
  // chainId: 56,
  // chainName: "BNB Smart Chain",
  // chainHex: "0x38",
  // rpcUrl: "https://bsc-dataseed.binance.org",
  // explorer: "https://bscscan.com",
  // agentPassAddress: "0x0000000000000000000000000000000000000000", // TODO: mainnet AgentPass address
  // agentIdRegistryAddress: "0x60b9262456de011f7d15a54cdd8c48baaa8b022f", // SPACE ID Agent ID (mainnet)
};
