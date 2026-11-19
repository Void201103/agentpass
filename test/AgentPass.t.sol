// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AgentPass.sol";

/// @notice Minimal stand-in for the SPACE ID Agent ID registry (testnet has none).
contract MockAgentID {
    mapping(address => uint256) public balanceOf;

    function setBalance(address who, uint256 n) external {
        balanceOf[who] = n;
    }
}

contract AgentPassTest is Test {
    AgentPass public pass;
    MockAgentID public registry;

    address public owner = address(this);
    address public organizer = address(0xA11CE);
    address public holder1 = address(0xB001);
    address public holder2 = address(0xB002);
    address public nonHolder = address(0xB003);

    uint256 public constant T0 = 1_800_000_000; // fixed "now" for tests
    uint256 public constant START = T0 + 1 days;
    uint256 public constant END = T0 + 2 days;

    function setUp() public {
        vm.warp(T0);
        registry = new MockAgentID();
        registry.setBalance(organizer, 1);
        registry.setBalance(holder1, 1);
        registry.setBalance(holder2, 1);
        // nonHolder keeps balance 0
        pass = new AgentPass(address(registry), owner, "https://agentpass.example/api/");
        assertEq(pass.owner(), owner); // owner is explicit, never the deployer/factory
    }

    function _createEvent(uint256 maxSupply, string memory metadataURI)
        internal
        returns (uint256)
    {
        vm.prank(organizer);
        return pass.createEvent(
            "AgentPass Launch - Founding Agents",
            "First AgentPass event",
            START,
            END,
            maxSupply,
            metadataURI
        );
    }

    function _createDefaultEvent() internal returns (uint256) {
        return _createEvent(100, "ipfs://QmEventMetadata");
    }

    // ------------------------------------------------------------------------
    // Event creation
    // ------------------------------------------------------------------------
    function testConstructorOwnerIsExplicit() public {
        // Deploying through a CREATE2 factory must not make the factory the owner.
        address other = address(0xC0FFEE);
        AgentPass second = new AgentPass(address(registry), other, "");
        assertEq(second.owner(), other);
        assertEq(pass.owner(), owner);
    }

    function testCreateEventSuccess() public {
        uint256 eventId = _createDefaultEvent();
        assertEq(eventId, 1);
        AgentPass.Event memory ev = pass.getEvent(1);
        assertEq(ev.name, "AgentPass Launch - Founding Agents");
        assertEq(ev.organizer, organizer);
        assertEq(ev.startTime, START);
        assertEq(ev.endTime, END);
        assertEq(ev.maxSupply, 100);
        assertEq(ev.minted, 0);
        assertTrue(ev.exists);
        assertEq(pass.totalEvents(), 1);
    }

    function testCreateEventRequiresAgentID() public {
        vm.prank(nonHolder);
        vm.expectRevert(AgentPass.NotAgentIDHolder.selector);
        pass.createEvent("Nope", "", START, END, 10, "");
    }

    function testCreateEventInvalidWindow() public {
        vm.prank(organizer);
        vm.expectRevert(AgentPass.InvalidEventWindow.selector);
        pass.createEvent("Bad", "", END, START, 10, ""); // end < start

        vm.prank(organizer);
        vm.expectRevert(AgentPass.InvalidEventWindow.selector);
        pass.createEvent("Bad", "", T0 - 2 days, T0 - 1 days, 10, ""); // ended in past
    }

    function testCreateEventZeroSupply() public {
        vm.prank(organizer);
        vm.expectRevert(AgentPass.InvalidMaxSupply.selector);
        pass.createEvent("Zero", "", START, END, 0, "");
    }

    function testCreateEventEmptyName() public {
        vm.prank(organizer);
        vm.expectRevert(AgentPass.EmptyName.selector);
        pass.createEvent("", "", START, END, 10, "");
    }

    function testEventCreationPaused() public {
        pass.setEventCreationPaused(true);
        assertTrue(pass.eventCreationPaused());
        vm.prank(organizer);
        vm.expectRevert(AgentPass.EventCreationPaused.selector);
        pass.createEvent("Paused", "", START, END, 10, "");
        pass.setEventCreationPaused(false);
        uint256 eventId = _createDefaultEvent();
        assertEq(eventId, 1);
    }

    function testSetEventCreationPausedOnlyOwner() public {
        vm.prank(holder1);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("OwnableUnauthorizedAccount(address)")),
                holder1
            )
        );
        pass.setEventCreationPaused(true);
    }

    function testSetBaseURIOnlyOwner() public {
        vm.prank(holder1);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("OwnableUnauthorizedAccount(address)")),
                holder1
            )
        );
        pass.setBaseURI("https://evil.example/");
    }

    // ------------------------------------------------------------------------
    // Claims
    // ------------------------------------------------------------------------
    function testClaimSuccess() public {
        uint256 eventId = _createDefaultEvent();
        vm.warp(START + 1 hours);
        vm.prank(holder1);
        uint256 tokenId = pass.claim(eventId);
        assertEq(tokenId, 1);
        assertEq(pass.balanceOf(holder1), 1);
        assertEq(pass.ownerOf(1), holder1);
        assertTrue(pass.hasClaimed(eventId, holder1));
        assertEq(pass.tokenEvent(1), eventId);
        assertEq(pass.totalMinted(), 1);
        // event had a custom metadataURI -> tokenURI returns it
        assertEq(pass.tokenURI(1), "ipfs://QmEventMetadata");
    }

    function testClaimBaseURIFallback() public {
        uint256 eventId = _createEvent(10, ""); // no custom metadataURI
        vm.warp(START + 1 hours);
        vm.prank(holder1);
        uint256 tokenId = pass.claim(eventId);
        assertEq(pass.tokenURI(tokenId), "https://agentpass.example/api/1");
    }

    function testClaimWithoutAgentID() public {
        uint256 eventId = _createDefaultEvent();
        vm.warp(START + 1 hours);
        vm.prank(nonHolder);
        vm.expectRevert(AgentPass.NotAgentIDHolder.selector);
        pass.claim(eventId);
    }

    function testClaimTwice() public {
        uint256 eventId = _createDefaultEvent();
        vm.warp(START + 1 hours);
        vm.prank(holder1);
        pass.claim(eventId);
        vm.prank(holder1);
        vm.expectRevert(AgentPass.AlreadyClaimed.selector);
        pass.claim(eventId);
    }

    function testClaimBeforeWindow() public {
        uint256 eventId = _createDefaultEvent();
        vm.warp(START - 1 hours);
        vm.prank(holder1);
        vm.expectRevert(AgentPass.ClaimWindowNotOpen.selector);
        pass.claim(eventId);
    }

    function testClaimAfterWindow() public {
        uint256 eventId = _createDefaultEvent();
        vm.warp(END + 1 hours);
        vm.prank(holder1);
        vm.expectRevert(AgentPass.ClaimWindowNotOpen.selector);
        pass.claim(eventId);
    }

    function testClaimSupplyExhausted() public {
        uint256 eventId = _createEvent(1, "");
        vm.warp(START + 1 hours);
        vm.prank(holder1);
        pass.claim(eventId);
        vm.prank(holder2);
        vm.expectRevert(AgentPass.SupplyExhausted.selector);
        pass.claim(eventId);
    }

    function testClaimNonexistentEvent() public {
        vm.warp(START + 1 hours);
        vm.prank(holder1);
        vm.expectRevert(AgentPass.EventDoesNotExist.selector);
        pass.claim(999);
    }

    // ------------------------------------------------------------------------
    // Soulbound
    // ------------------------------------------------------------------------
    function testTransferReverts() public {
        uint256 eventId = _createDefaultEvent();
        vm.warp(START + 1 hours);
        vm.prank(holder1);
        pass.claim(eventId);

        vm.prank(holder1);
        vm.expectRevert(AgentPass.SoulboundTransferBlocked.selector);
        pass.transferFrom(holder1, holder2, 1);

        vm.prank(holder1);
        vm.expectRevert(AgentPass.SoulboundTransferBlocked.selector);
        pass.safeTransferFrom(holder1, holder2, 1);

        // badge still with holder1
        assertEq(pass.ownerOf(1), holder1);
    }

    function testApproveReverts() public {
        uint256 eventId = _createDefaultEvent();
        vm.warp(START + 1 hours);
        vm.prank(holder1);
        pass.claim(eventId);

        vm.prank(holder1);
        vm.expectRevert(AgentPass.SoulboundApprovalBlocked.selector);
        pass.approve(holder2, 1);
    }

    function testSetApprovalForAllReverts() public {
        vm.prank(holder1);
        vm.expectRevert(AgentPass.SoulboundApprovalBlocked.selector);
        pass.setApprovalForAll(holder2, true);
    }

    // ------------------------------------------------------------------------
    // Views / misc
    // ------------------------------------------------------------------------
    function testGetEventNonexistent() public {
        vm.expectRevert(AgentPass.EventDoesNotExist.selector);
        pass.getEvent(999);
    }

    function testTokenURINonexistent() public {
        vm.expectRevert(AgentPass.TokenDoesNotExist.selector);
        pass.tokenURI(999);
    }

    function testIsAgentIDHolder() public {
        assertTrue(pass.isAgentIDHolder(holder1));
        assertFalse(pass.isAgentIDHolder(nonHolder));
        assertEq(address(pass.agentIdRegistry()), address(registry));
    }
}
