class_name NetSim
extends Node
## UDP latency and loss proxy for tests (debug builds only; the launch flags that start it
## are ignored in release builds). The forwarding loop is adapted from
## addons/netfox.extras/network-simulator.gd (netfox v1.49.12, MIT licence, (c) Fox's Sake
## Studio); the stock node cannot be used because it creates its own connection and only
## runs with the "editor" feature tag.
##
## The host's ENet server listens on port P. This proxy listens on P + 1 and forwards to P.
## A client that wants simulated conditions connects to P + 1. Every packet is held for
## latency_ms in each direction, so the measured round trip is about twice latency_ms. With
## jitter_ms each packet is held a further random 0 to jitter_ms, so packets can also arrive
## out of order.
## Both the host and the client must be started with the same flags.

const HOST_ADDRESS: String = "127.0.0.1"
## Seed of the loss generator, fixed so a run is repeatable.
const LOSS_SEED: int = 12345

var _server_port: int = 0
var _latency_ms: int = 0
var _loss_percent: float = 0.0
var _jitter_ms: int = 0
var _thread: Thread
var _running: bool = true
var _socket: PacketPeerUDP
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Client UDP port -> socket that talks to the server on that client's behalf.
var _client_peers: Dictionary[int, PacketPeerUDP] = {}
var _to_server: Array[QueueEntry] = []
var _to_client: Array[QueueEntry] = []

class QueueEntry:
	var packet: PackedByteArray
	var queued_at: int
	var client_port: int
	var delay_ms: int

	func _init(p_packet: PackedByteArray, p_queued_at: int, p_client_port: int, p_delay_ms: int) -> void:
		packet = p_packet
		queued_at = p_queued_at
		client_port = p_client_port
		delay_ms = p_delay_ms

## Start forwarding. loss_percent is a percentage (5.0 drops one packet in twenty).
func start(server_port: int, latency_ms: int, loss_percent: float, jitter_ms: int = 0) -> void:
	_jitter_ms = jitter_ms
	_server_port = server_port
	_latency_ms = latency_ms
	_loss_percent = loss_percent
	_rng.seed = LOSS_SEED
	_socket = PacketPeerUDP.new()
	var status: Error = _socket.bind(server_port + 1, HOST_ADDRESS)
	if status != OK:
		push_error("NetSim: could not bind port %d: %s" % [server_port + 1, error_string(status)])
		return
	_thread = Thread.new()
	_thread.start(_loop)
	print("NETSIM latency_ms=%d jitter_ms=%d loss_percent=%.2f proxy_port=%d" % [latency_ms, jitter_ms, loss_percent, server_port + 1])

func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_running = false
		_thread.wait_to_finish()

func _loop() -> void:
	while _running:
		var now: int = Time.get_ticks_msec()
		_read_from_clients(now)
		_forward_to_server(now)
		_read_from_server(now)
		_forward_to_clients(now)
		OS.delay_msec(1)

func _read_from_clients(now: int) -> void:
	while _socket.get_available_packet_count() > 0:
		var packet: PackedByteArray = _socket.get_packet()
		if _socket.get_packet_error() != OK:
			continue
		var from_port: int = _socket.get_packet_port()
		if not _client_peers.has(from_port):
			var peer: PacketPeerUDP = PacketPeerUDP.new()
			peer.set_dest_address(HOST_ADDRESS, _server_port)
			_client_peers[from_port] = peer
		_to_server.push_back(QueueEntry.new(packet, now, from_port, _delay()))

func _forward_to_server(now: int) -> void:
	var keep: Array[QueueEntry] = []
	for entry: QueueEntry in _to_server:
		if now - entry.queued_at < entry.delay_ms:
			keep.append(entry)
		elif _keeps_packet():
			_client_peers[entry.client_port].put_packet(entry.packet)
	_to_server = keep

func _read_from_server(now: int) -> void:
	for client_port: int in _client_peers:
		var peer: PacketPeerUDP = _client_peers[client_port]
		while peer.get_available_packet_count() > 0:
			var packet: PackedByteArray = peer.get_packet()
			if peer.get_packet_error() != OK:
				continue
			_to_client.push_back(QueueEntry.new(packet, now, client_port, _delay()))

func _forward_to_clients(now: int) -> void:
	var keep: Array[QueueEntry] = []
	for entry: QueueEntry in _to_client:
		if now - entry.queued_at < entry.delay_ms:
			keep.append(entry)
		elif _keeps_packet():
			_socket.set_dest_address(HOST_ADDRESS, entry.client_port)
			_socket.put_packet(entry.packet)
	_to_client = keep

func _keeps_packet() -> bool:
	return _loss_percent <= 0.0 or _rng.randf() >= _loss_percent / 100.0

func _delay() -> int:
	return _latency_ms + (_rng.randi_range(0, _jitter_ms) if _jitter_ms > 0 else 0)
