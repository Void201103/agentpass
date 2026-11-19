// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/AgentPass.sol";

/// @notice Mainnet deploy: AgentPass with the real SPACE ID Agent ID registry.
/// @dev Env: PRIVATE_KEY (deployer), BASE_URI (optional, default empty).
///      Owner is an explicit constructor param (0xvoid.ai) — NOT the deployer,
///      so the same bytecode can be deployed through a CREATE2 factory.
contract Deploy is Script {
    address public constant AGENT_ID_REGISTRY =
        0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F; // SPACE ID Agent ID, BNB Chain
    address public constant OWNER =
        0x4DEdeC3f5a3bf02b3525AAa15c3374af74cC4837; // 0xvoid.ai

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        string memory baseURI = vm.envOr("BASE_URI", string(""));
        vm.startBroadcast(deployerKey);
        AgentPass pass = new AgentPass(AGENT_ID_REGISTRY, OWNER, baseURI);
        vm.stopBroadcast();
        console.log("AgentPass deployed at:", address(pass));
        console.log("Owner (0xvoid.ai):", OWNER);
        console.log("Agent ID registry:", AGENT_ID_REGISTRY);
    }
}
