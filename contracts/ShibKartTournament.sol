// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ShibKartTournament
/// @notice Racing tournament escrow for ShibKart. Sponsor seeds a pot and/or players
///         pay an entry fee into the pot; races run OFF-CHAIN (Supabase realtime) across
///         many maps; the match server (`resultSigner`) signs the final standings, and
///         anyone can submit them to pay out the podium. Mirrors WutTournament's
///         signer-settlement pattern but supports entry-fee pooling + multi-place payouts.
contract ShibKartTournament {
    struct Tournament {
        address sponsor;
        uint96  pot;
        uint16  maxPlayers;
        uint96  entryFee;
        uint8   races;
        bool    closed;
        bool    locked;
        bool    settled;
        uint64  lockedAt;
    }

    uint64 public constant ABANDON_AFTER = 7 days;
    address public immutable resultSigner;

    uint256 public nextId;
    mapping(uint256 => Tournament) public tournaments;
    mapping(uint256 => address[]) private _players;
    mapping(uint256 => mapping(address => bool)) public joined;
    mapping(uint256 => mapping(address => bool)) public allowlist;

    event RaceTournamentCreated(uint256 indexed id, address sponsor, uint96 pot, uint96 entryFee, uint16 maxPlayers, uint8 races, bool closed);
    event PlayerJoined(uint256 indexed id, address player, uint256 playerCount);
    event Locked(uint256 indexed id, uint256 playerCount);
    event Settled(uint256 indexed id, uint256 winners, uint96 total);
    event Payout(uint256 indexed id, address to, uint96 amount);
    event Cancelled(uint256 indexed id);
    event Reclaimed(uint256 indexed id);

    constructor(address signer) { resultSigner = signer; }

    function createTournament(uint16 maxPlayers, uint96 entryFee, uint8 races, bool closed) external payable returns (uint256 id) {
        require(maxPlayers >= 2, "min 2");
        id = nextId++;
        tournaments[id] = Tournament(msg.sender, uint96(msg.value), maxPlayers, entryFee, races, closed, false, false, 0);
        emit RaceTournamentCreated(id, msg.sender, uint96(msg.value), entryFee, maxPlayers, races, closed);
    }

    function addToAllowlist(uint256 id, address[] calldata who) external {
        require(msg.sender == tournaments[id].sponsor, "not sponsor");
        for (uint256 i; i < who.length; i++) allowlist[id][who[i]] = true;
    }

    function join(uint256 id) external payable {
        Tournament storage t = tournaments[id];
        require(!t.locked && !t.settled, "closed");
        require(_players[id].length < t.maxPlayers, "full");
        require(!joined[id][msg.sender], "joined");
        require(msg.value == t.entryFee, "bad fee");
        if (t.closed) require(allowlist[id][msg.sender], "not allowed");
        joined[id][msg.sender] = true;
        _players[id].push(msg.sender);
        t.pot += uint96(msg.value);
        emit PlayerJoined(id, msg.sender, _players[id].length);
    }

    function lock(uint256 id) external {
        Tournament storage t = tournaments[id];
        require(msg.sender == t.sponsor, "not sponsor");
        require(!t.locked, "locked");
        t.locked = true;
        t.lockedAt = uint64(block.timestamp);
        emit Locked(id, _players[id].length);
    }

    /// @notice Pay out the podium using the match server's signature over the standings.
    function finalize(uint256 id, address[] calldata winners, uint96[] calldata amounts, uint8 v, bytes32 r, bytes32 s) external {
        Tournament storage t = tournaments[id];
        require(t.locked && !t.settled, "state");
        require(winners.length == amounts.length && winners.length > 0, "len");
        bytes32 h = keccak256(abi.encode(address(this), block.chainid, id, winners, amounts));
        bytes32 eth = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", h));
        require(ecrecover(eth, v, r, s) == resultSigner, "bad sig");
        uint96 total;
        for (uint256 i; i < amounts.length; i++) total += amounts[i];
        require(total <= t.pot, "over pot");
        t.settled = true;
        for (uint256 i; i < winners.length; i++) {
            (bool ok, ) = winners[i].call{value: amounts[i]}("");
            require(ok, "pay");
            emit Payout(id, winners[i], amounts[i]);
        }
        emit Settled(id, winners.length, total);
    }

    function cancel(uint256 id) external {
        Tournament storage t = tournaments[id];
        require(msg.sender == t.sponsor && !t.locked && !t.settled, "no");
        t.settled = true;
        uint96 p = t.pot; t.pot = 0;
        (bool ok, ) = t.sponsor.call{value: p}(""); require(ok, "refund");
        emit Cancelled(id);
    }

    function reclaimAbandoned(uint256 id) external {
        Tournament storage t = tournaments[id];
        require(t.locked && !t.settled && block.timestamp > t.lockedAt + ABANDON_AFTER, "no");
        t.settled = true;
        uint96 p = t.pot; t.pot = 0;
        (bool ok, ) = t.sponsor.call{value: p}(""); require(ok, "refund");
        emit Reclaimed(id);
    }

    function playersOf(uint256 id) external view returns (address[] memory) { return _players[id]; }
}
