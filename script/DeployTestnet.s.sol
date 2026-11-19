// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/AgentPass.sol";

/// @notice Test-only stand-in for the Agent ID registry (BSC testnet has none).
/// @dev Deployed by the testnet script only. NOT used on mainnet.
contract MockAgentID {
    mapping(address => uint256) public balanceOf;

    function setBalance(address who, uint256 n) external {
        balanceOf[who] = n;
    }
}

/// @notice Testnet deploy: mock registry -> grant deployer a mock Agent ID ->
///         deploy AgentPass -> create the first event.
/// @dev Env: PRIVATE_KEY (deployer), BASE_URI (optional).
contract DeployTestnet is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        string memory baseURI = vm.envOr("BASE_URI", string(""));

        vm.startBroadcast(deployerKey);
        MockAgentID mock = new MockAgentID();
        mock.setBalance(deployer, 1);
        AgentPass pass = new AgentPass(address(mock), deployer, baseURI);
        uint256 eventId = pass.createEvent(
            "AgentPass Launch - Founding Agents",
            "First AgentPass event. Claim your founding badge.",
            block.timestamp,
            block.timestamp + 7 days,
            100,
            ""
        );
        vm.stopBroadcast();

        console.log("MockAgentID deployed at:", address(mock));
        console.log("AgentPass deployed at:", address(pass));
        console.log("Owner (deployer):", deployer);
        console.log("First event id:", eventId);
    }
}
