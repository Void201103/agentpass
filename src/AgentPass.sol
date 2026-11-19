// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/// @notice Minimal interface of the SPACE ID Agent ID registry (ERC-721, non-transferable).
/// @dev Mainnet (BNB Chain): 0x60b9262456de011f7d15a54cdd8c48baaa8b022f
///      Only balanceOf is needed: a return value > 0 means the address holds an Agent ID.
interface IAgentID {
    function balanceOf(address owner) external view returns (uint256);
}

/// @title AgentPass
/// @notice Soulbound attendance badges (POAP-style) for Agent ID holders at community events.
/// @dev A single contract: event registry + ERC-721 badge. Badges are soulbound:
///      any transfer between two non-zero addresses reverts, and approvals are disabled.
///      Claiming is free (gas only). No payment, no promised returns, no fund movement.
///      Agent ID is checked on-chain for BOTH creating events and claiming badges.
///      The contract never takes custody of user assets and cannot move user funds.
contract AgentPass is ERC721, Ownable {
    using Strings for uint256;

    // ------------------------------------------------------------------------
    // Errors
    // ------------------------------------------------------------------------
    error NotAgentIDHolder();
    error EventDoesNotExist();
    error EventCreationPaused();
    error InvalidEventWindow();
    error InvalidMaxSupply();
    error EmptyName();
    error ClaimWindowNotOpen();
    error AlreadyClaimed();
    error SupplyExhausted();
    error SoulboundTransferBlocked();
    error SoulboundApprovalBlocked();
    error TokenDoesNotExist();

    // ------------------------------------------------------------------------
    // Storage
    // ------------------------------------------------------------------------
    /// @notice The Agent ID registry contract (immutable after deploy).
    IAgentID public immutable agentIdRegistry;

    /// @notice Base URI used for tokenURI when an event has no custom metadataURI.
    string private _baseTokenURI;

    /// @notice When true, no new events can be created (owner-only switch).
    bool public eventCreationPaused;

    /// @notice Next event id to assign (starts at 1).
    uint256 public nextEventId = 1;

    /// @notice Next badge token id to assign (starts at 1).
    uint256 public nextTokenId = 1;

    struct Event {
        string name;
        string description;
        uint256 startTime;
        uint256 endTime;
        uint256 maxSupply;
        uint256 minted;
        string metadataURI;
        address organizer;
        bool exists;
    }

    /// @notice eventId => Event
    mapping(uint256 => Event) public events;

    /// @notice tokenId => eventId the badge was claimed for
    mapping(uint256 => uint256) public tokenEvent;

    /// @notice eventId => claimer => already claimed
    mapping(uint256 => mapping(address => bool)) public hasClaimed;

    // ------------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------------
    event EventCreated(
        uint256 indexed eventId,
        address indexed organizer,
        string name,
        uint256 startTime,
        uint256 endTime,
        uint256 maxSupply
    );
    event BadgeClaimed(
        uint256 indexed eventId,
        uint256 indexed tokenId,
        address indexed claimer
    );
    event BaseURIUpdated(string baseURI);
    event EventCreationPausedUpdated(bool paused);

    // ------------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------------
    /// @param _agentIdRegistry Address of the Agent ID registry contract.
    /// @param _owner Explicit owner address (admin for setBaseURI / setEventCreationPaused).
    ///      The owner is a constructor parameter — NOT msg.sender — so the contract can be
    ///      deployed through a CREATE2 factory, where msg.sender at construction is the
    ///      factory itself. On mainnet this is 0xvoid.ai (0x4DEdeC3f5a3bf02b3525AAa15c3374af74cC4837).
    /// @param baseURI_ Base URI for token metadata (may be empty; per-event metadataURI takes precedence).
    constructor(address _agentIdRegistry, address _owner, string memory baseURI_)
        ERC721("AgentPass", "APASS")
        Ownable(_owner)
    {
        require(_agentIdRegistry != address(0), "registry is zero address");
        require(_owner != address(0), "owner is zero address");
        agentIdRegistry = IAgentID(_agentIdRegistry);
        _baseTokenURI = baseURI_;
    }

    // ------------------------------------------------------------------------
    // Organizer functions
    // ------------------------------------------------------------------------
    /// @notice Create a new event. Caller must hold an Agent ID.
    /// @param name Event name (required, non-empty).
    /// @param description Event description (may be empty).
    /// @param startTime Unix timestamp when claiming opens.
    /// @param endTime Unix timestamp when claiming closes (must be > startTime and in the future).
    /// @param maxSupply Maximum number of badges for this event (must be > 0).
    /// @param metadataURI Optional metadata URI shared by all badges of this event (may be empty).
    /// @return eventId The id of the newly created event.
    function createEvent(
        string calldata name,
        string calldata description,
        uint256 startTime,
        uint256 endTime,
        uint256 maxSupply,
        string calldata metadataURI
    ) external returns (uint256 eventId) {
        if (eventCreationPaused) revert EventCreationPaused();
        if (agentIdRegistry.balanceOf(msg.sender) == 0) revert NotAgentIDHolder();
        if (bytes(name).length == 0) revert EmptyName();
        if (startTime >= endTime || endTime <= block.timestamp) revert InvalidEventWindow();
        if (maxSupply == 0) revert InvalidMaxSupply();

        eventId = nextEventId++;
        events[eventId] = Event({
            name: name,
            description: description,
            startTime: startTime,
            endTime: endTime,
            maxSupply: maxSupply,
            minted: 0,
            metadataURI: metadataURI,
            organizer: msg.sender,
            exists: true
        });

        emit EventCreated(eventId, msg.sender, name, startTime, endTime, maxSupply);
    }

    // ------------------------------------------------------------------------
    // Claim functions
    // ------------------------------------------------------------------------
    /// @notice Claim one soulbound badge for an event. Caller must hold an Agent ID.
    /// @dev Free: no payment. One badge per Agent ID holder per event.
    /// @param eventId The event to claim a badge for.
    /// @return tokenId The id of the newly minted badge.
    function claim(uint256 eventId) external returns (uint256 tokenId) {
        Event storage ev = events[eventId];
        if (!ev.exists) revert EventDoesNotExist();
        if (block.timestamp < ev.startTime || block.timestamp > ev.endTime) {
            revert ClaimWindowNotOpen();
        }
        if (agentIdRegistry.balanceOf(msg.sender) == 0) revert NotAgentIDHolder();
        if (hasClaimed[eventId][msg.sender]) revert AlreadyClaimed();
        if (ev.minted >= ev.maxSupply) revert SupplyExhausted();

        tokenId = nextTokenId++;
        ev.minted += 1;
        hasClaimed[eventId][msg.sender] = true;
        tokenEvent[tokenId] = eventId;

        _safeMint(msg.sender, tokenId);
        emit BadgeClaimed(eventId, tokenId, msg.sender);
    }

    // ------------------------------------------------------------------------
    // Soulbound enforcement
    // ------------------------------------------------------------------------
    /// @dev Blocks every transfer between two non-zero addresses.
    ///      Minting (from == address(0)) is allowed; burning (to == address(0))
    ///      is allowed at the contract level but no burn function is exposed.
    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        returns (address)
    {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) {
            revert SoulboundTransferBlocked();
        }
        return super._update(to, tokenId, auth);
    }

    /// @dev Approvals are meaningless for a soulbound token; block them explicitly
    ///      so wallets and marketplaces cannot mislead users into approving transfers.
    function approve(address /* to */, uint256 /* tokenId */) public pure override {
        revert SoulboundApprovalBlocked();
    }

    /// @dev See {approve}.
    function setApprovalForAll(address /* operator */, bool /* approved */) public pure override {
        revert SoulboundApprovalBlocked();
    }

    // ------------------------------------------------------------------------
    // Owner functions (minimal, documented in README)
    // ------------------------------------------------------------------------
    /// @notice Update the base URI used when an event has no custom metadataURI.
    /// @dev Owner-only. Does not affect badges whose event sets metadataURI.
    function setBaseURI(string calldata baseURI_) external onlyOwner {
        _baseTokenURI = baseURI_;
        emit BaseURIUpdated(baseURI_);
    }

    /// @notice Pause or unpause creation of new events. Existing events and claims are unaffected.
    /// @dev Owner-only. Emergency spam brake only.
    function setEventCreationPaused(bool paused) external onlyOwner {
        eventCreationPaused = paused;
        emit EventCreationPausedUpdated(paused);
    }

    // ------------------------------------------------------------------------
    // Views
    // ------------------------------------------------------------------------
    /// @notice Full event record.
    function getEvent(uint256 eventId) external view returns (Event memory) {
        if (!events[eventId].exists) revert EventDoesNotExist();
        return events[eventId];
    }

    /// @notice Total number of badges ever minted.
    function totalMinted() external view returns (uint256) {
        return nextTokenId - 1;
    }

    /// @notice Total number of events ever created.
    function totalEvents() external view returns (uint256) {
        return nextEventId - 1;
    }

    /// @notice Metadata URI for a badge: the event's custom metadataURI when set,
    ///         otherwise baseURI + tokenId. Reverts for nonexistent tokens.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();
        string memory eventURI = events[tokenEvent[tokenId]].metadataURI;
        if (bytes(eventURI).length > 0) {
            return eventURI;
        }
        return string.concat(_baseTokenURI, tokenId.toString());
    }

    /// @notice Whether an address holds an Agent ID (registry balance > 0).
    function isAgentIDHolder(address account) external view returns (bool) {
        return agentIdRegistry.balanceOf(account) > 0;
    }
}
