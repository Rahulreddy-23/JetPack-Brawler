class_name Session
extends Node
## Starts and stops the ENet connection. Solo play is a host with no clients.
## The server owns everything; this node only creates and closes the peer.
## It defines no RPCs.

## The host went away, the match was full, or the connection could not be made.
signal ended(message: String)
## The server let this peer in; it may now get a bot.
signal peer_accepted(id: int)

const MATCH_FULL_MESSAGE: String = "Match full. Try again when someone leaves."

var _active: bool = false
var _reason: String = ""
var _cfg: TuningConfig = TuningConfig.get_default()

func _ready() -> void:
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	NetworkEvents.on_peer_join.connect(_on_peer_join)

## True while hosting or connected.
func is_active() -> bool:
	return _active

## Start a host. max_players counts the host itself. One spare slot lets a
## player past the limit connect long enough to be told the match is full.
func host(port: int, max_players: int) -> Error:
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(port, max_players - 1 + _cfg.spare_connection_slots)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_active = true
	_reason = ""
	return OK

## Connect to a host at a typed IP address.
func join(address: String, port: int) -> Error:
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_active = true
	_reason = ""
	return OK

## Close the connection and go back to offline.
func leave() -> void:
	# netfox only stops its clock when the server drops us, not when we close our
	# own peer, so a second join would find the clock still running and never sync.
	NetworkTime.stop()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_active = false

## Non-loopback IPv4 addresses of this machine, for the host screen.
static func local_ipv4_addresses() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for address: String in IP.get_local_addresses():
		if address.count(".") == 3 and not address.begins_with("127.") and not address.begins_with("169.254."):
			result.append(address)
	return result

# Server only. Every connected peer counts, including ones still syncing their
# clock, plus the host's own bot.
func _on_peer_join(id: int) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_peers().size() + 1 > _cfg.max_players:
		_match_full.rpc_id(id)
		# ENet drops packets still queued for a peer when it is disconnected, so
		# give the notice time to leave first.
		await get_tree().create_timer(_cfg.reject_notice_seconds).timeout
		if multiplayer.get_peers().has(id):
			multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	peer_accepted.emit(id)

# Only the server (this node's authority) may call this; clients just receive it.
@rpc("authority", "call_remote", "reliable")
func _match_full() -> void:
	_reason = MATCH_FULL_MESSAGE

func _on_connection_failed() -> void:
	leave()
	ended.emit("Could not connect. Check the address and that the host is running and not full.")

func _on_server_disconnected() -> void:
	leave()
	ended.emit(_reason if not _reason.is_empty() else "The host went away.")
