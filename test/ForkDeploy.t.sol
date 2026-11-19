// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AgentPass.sol";

/// @notice Fork simulation of the real mainnet deploy path:
///  0xvoid (Agent ID holder) sends a raw tx to the Arachnid deterministic
///  deployment proxy with data = salt || initCode (no function selector),
///  then creates the launch event and claims badges (0xvoid + titutt).
///  Run: forge test --match-contract ForkDeployTest --fork-url https://bsc-dataseed.binance.org -vv
contract ForkDeployTest is Test {
    address public constant FACTORY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    address public constant REGISTRY = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;
    address public constant VOID = 0x4DEdeC3f5a3bf02b3525AAa15c3374af74cC4837;
    address public constant TITUTT = 0x173765e5E22945Cb777Da4ac8f992CfcB3ADF341;
    bytes32 public constant SALT = 0x2c05c5ee6c16729f86e65dc62906c60ca94d377da7c24e4bd0eae13666e369db;
    address public constant EXPECTED = 0xB097e4968BD615748162d999a01eADdcec853055;

    bytes public initCode;

    function setUp() public {
        // Pin the fork to the block BEFORE the real mainnet deploy (block
        // 134505093) so the expected CREATE2 address is still empty and the
        // test simulates the deploy itself. Without the pin, the fork lands
        // on latest mainnet where the contract already lives at EXPECTED.
        // RPC must serve historical state at that block: the Binance dataseed
        // nodes prune it (missing trie node); publicnode serves it.
        vm.createSelectFork("https://bsc.publicnode.com", 134505092);
        bytes memory creation = vm.getCode("AgentPass.sol:AgentPass");
        initCode = abi.encodePacked(creation, abi.encode(REGISTRY, VOID, ""));
        // The init code must match the one computed offline (keccak pinned).
        assertEq(
            keccak256(initCode),
            0x2099b14d72714d6b5f37543890e75385a3327bec5d2545d57b6c8a1702498cbb,
            "initCode keccak mismatch vs offline computation"
        );
    }

    function testForkDeployViaFactoryAndClaim() public {
        // Sanity: both wallets really hold an Agent ID on mainnet.
        assertGt(IAgentID(REGISTRY).balanceOf(VOID), 0, "0xvoid has no Agent ID");
        assertGt(IAgentID(REGISTRY).balanceOf(TITUTT), 0, "titutt has no Agent ID");
        assertEq(EXPECTED.code.length, 0, "expected address not empty");

        // 1) Deploy via factory (raw tx: salt || initCode), as 0xvoid.
        uint256 gasBefore = gasleft();
        vm.prank(VOID);
        (bool ok, ) = FACTORY.call(abi.encodePacked(SALT, initCode));
        uint256 deployInnerGas = gasBefore - gasleft();
        assertTrue(ok, "factory deploy call failed");
        assertGt(EXPECTED.code.length, 0, "no code at expected address");
        emit log_named_uint("deploy inner gas (excl tx base + calldata)", deployInnerGas);

        AgentPass pass = AgentPass(EXPECTED);
        assertEq(pass.owner(), VOID, "owner is not 0xvoid");
        assertEq(address(pass.agentIdRegistry()), REGISTRY, "registry mismatch");

        // 2) Create the launch event as 0xvoid.
        gasBefore = gasleft();
        vm.prank(VOID);
        uint256 eventId = pass.createEvent(
            "AgentPass Launch - Founding Agents",
            "First AgentPass event",
            block.timestamp,
            block.timestamp + 7 days,
            100,
            ""
        );
        uint256 createGas = gasBefore - gasleft();
        assertEq(eventId, 1, "first event id != 1");
        emit log_named_uint("createEvent gas", createGas);

        // 3) Claim as 0xvoid.
        gasBefore = gasleft();
        vm.prank(VOID);
        uint256 token1 = pass.claim(1);
        uint256 claimGas1 = gasBefore - gasleft();
        assertEq(token1, 1, "first token id != 1");
        assertEq(pass.ownerOf(1), VOID, "badge 1 owner != 0xvoid");
        emit log_named_uint("claim gas (0xvoid)", claimGas1);

        // 4) Claim as titutt (second Agent ID holder).
        gasBefore = gasleft();
        vm.prank(TITUTT);
        uint256 token2 = pass.claim(1);
        uint256 claimGas2 = gasBefore - gasleft();
        assertEq(token2, 2, "second token id != 2");
        assertEq(pass.ownerOf(2), TITUTT, "badge 2 owner != titutt");
        emit log_named_uint("claim gas (titutt)", claimGas2);
    }
}

