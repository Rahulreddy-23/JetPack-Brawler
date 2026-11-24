extends Node
## Test support for the netfox handler tests. This node is its own subject: it
## has two int properties registered as rollback input, rollback state and
## synchronized state, and it builds the same packets the five synchronisation
## handlers receive, so the handlers can be called with chosen senders, ticks
## and bytes without a second process.

const PROP_A: NodePath = ^"a"
const PROP_B: NodePath = ^"b"

var a: int = 0
var b: int = 0

## Make the node the subject of the three property pools of the synchronisation
## server, which is what the handlers decode against. The history server needs no
## registration: merging creates the per-object history on demand. Call after
## the node is in the tree and the multiplayer peer is set.
func register(subject_name: String = "ProbeSubject") -> void:
	name = subject_name
	set_multiplayer_authority(multiplayer.get_unique_id())
	NetworkIdentityServer.register_node(self)
	for prop: NodePath in [PROP_A, PROP_B]:
		NetworkSynchronizationServer.register_rollback_input(self, prop)
		NetworkSynchronizationServer.register_rollback_state(self, prop)
		NetworkSynchronizationServer.register_sync_state(self, prop)

func unregister() -> void:
	NetworkSynchronizationServer.deregister(self)
	NetworkIdentityServer.deregister_node(self)

## A snapshot of this node at tick holding only the given properties (a
## NodePath to value Dictionary), marked as owned.
func snapshot_of(tick: int, values: Dictionary) -> _Snapshot:
	var snapshot: _Snapshot = _Snapshot.new(tick)
	for property: NodePath in values:
		snapshot.set_property(self, property, values[property])
	snapshot.set_auth(self, true)
	return snapshot

## A diff-state or diff-sync packet carrying only the given properties.
func diff_packet_of(tick: int, values: Dictionary, sync: bool) -> PackedByteArray:
	var server: _NetworkSynchronizationServer = NetworkSynchronizationServer
	var pool: _PropertyPool = server._sync_owned_state_properties if sync else server._rb_owned_state_properties
	return _as_local.call(func() -> PackedByteArray:
		return server._sparse_serializer.write_for(2, snapshot_of(tick, values), pool)[0]) as PackedByteArray

## A snapshot of this node at tick, both properties set, marked as owned.
func snapshot_at(tick: int, value: int) -> _Snapshot:
	var snapshot: _Snapshot = _Snapshot.new(tick)
	snapshot.set_property(self, PROP_A, value)
	snapshot.set_property(self, PROP_B, value)
	snapshot.set_auth(self, true)
	return snapshot

## Serialisation asserts the writer owns the node, so write as the local peer.
func _as_local(writer: Callable) -> Variant:
	var previous: int = get_multiplayer_authority()
	set_multiplayer_authority(multiplayer.get_unique_id())
	var result: Variant = writer.call()
	set_multiplayer_authority(previous)
	return result

func input_packet(tick: int, value: int) -> PackedByteArray:
	var sync: _NetworkSynchronizationServer = NetworkSynchronizationServer
	var snapshots: Array[_Snapshot] = [snapshot_at(tick, value)]
	return _as_local.call(func() -> PackedByteArray:
		return sync._redundant_serializer.write_for(2, snapshots, sync._rb_owned_input_properties)) as PackedByteArray

func full_state_packet(tick: int, value: int) -> PackedByteArray:
	var sync: _NetworkSynchronizationServer = NetworkSynchronizationServer
	return _as_local.call(func() -> PackedByteArray:
		return sync._dense_serializer.write_for(2, snapshot_at(tick, value), sync._rb_owned_state_properties)[0]) as PackedByteArray

func diff_state_packet(tick: int, value: int) -> PackedByteArray:
	var sync: _NetworkSynchronizationServer = NetworkSynchronizationServer
	return _as_local.call(func() -> PackedByteArray:
		return sync._sparse_serializer.write_for(2, snapshot_at(tick, value), sync._rb_owned_state_properties)[0]) as PackedByteArray

func full_sync_packet(tick: int, value: int) -> PackedByteArray:
	var sync: _NetworkSynchronizationServer = NetworkSynchronizationServer
	return _as_local.call(func() -> PackedByteArray:
		return sync._dense_serializer.write_for(2, snapshot_at(tick, value), sync._sync_owned_state_properties)[0]) as PackedByteArray

func diff_sync_packet(tick: int, value: int) -> PackedByteArray:
	var sync: _NetworkSynchronizationServer = NetworkSynchronizationServer
	return _as_local.call(func() -> PackedByteArray:
		return sync._sparse_serializer.write_for(2, snapshot_at(tick, value), sync._sync_owned_state_properties)[0]) as PackedByteArray

## A diff packet whose single frame for this node carries the given changed-bits
## byte(s) and a body of body_size zero bytes. Hand-built, so the bits can name
## properties the node does not have.
func crafted_diff_packet(tick: int, bits: PackedByteArray, body_size: int) -> PackedByteArray:
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	buffer.put_u32(tick)
	var identifier: _NetworkIdentifier = NetworkIdentityServer._get_identifier_of(self)
	NetworkSchemas._netref().encode(identifier.reference_for(2), buffer)
	NetworkSchemas.varuint().encode(body_size, buffer)
	buffer.put_data(bits)
	buffer.put_data(filled(body_size, 0))
	return buffer.data_array

static func filled(count: int, value: int) -> PackedByteArray:
	var result: PackedByteArray = PackedByteArray()
	result.resize(count)
	result.fill(value)
	return result

## Rewrite the tick (first four bytes) of a captured or built packet.
static func with_tick(packet: PackedByteArray, tick: int) -> PackedByteArray:
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	buffer.data_array = packet
	buffer.seek(0)
	buffer.put_u32(tick)
	return buffer.data_array
