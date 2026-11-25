extends Node
## Regression tests for active unmerged geminiceo fixes (G-28, G-29) against origin/main (50f7445).
## Every check fails (or crashes with SIGBUS) on origin/main without its fix.
## Run:
##   godot --headless --path . res://tests/test_security_audit.tscn
## Exits 0 when every check passes, 1 otherwise.

const TIMEOUT_SECONDS: float = 30.0

var _failures: int = 0
var _checks: int = 0

func _ready() -> void:
	get_tree().create_timer(TIMEOUT_SECONDS).timeout.connect(_on_timeout)
	_run()

func _on_timeout() -> void:
	print("FAIL timeout, security audit test did not finish")
	get_tree().quit(1)

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("PASS ", label)
	else:
		_failures += 1
		print("FAIL ", label)

func _run() -> void:
	_test_identity_serializer_length_guards()
	_test_string_schema_length_guards()
	_test_identity_server_packet_size_cap()
	_test_command_transport_truncated_prefix()
	print("%d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

func _test_identity_serializer_length_guards() -> void:
	var ser := _IdentityPacketSerializer.new()
	# Valid round-trip (ASCII, empty, and multibyte UTF-8) stays wire-compatible.
	var valid: Dictionary = {"/root/Main/Bots/Bot1/Input": 7, "": 0, "/root/Cafe\u00e9": 42}
	var decoded: Dictionary = ser.deserialize(ser.serialize(valid))
	_check(decoded == valid, "G-28a: valid identity packets still round-trip cleanly")

	# Crafted 4-byte 0x7fffffff length (SIGBUS on unpatched main), negative length, and truncated tail.
	var bad_huge: Dictionary = ser.deserialize(PackedByteArray([0xff, 0xff, 0xff, 0x7f]))
	var bad_neg: Dictionary = ser.deserialize(PackedByteArray([0xff, 0xff, 0xff, 0xff]))
	var bad_short: Dictionary = ser.deserialize(PackedByteArray([1]))
	var bad_trunc: Dictionary = ser.deserialize(PackedByteArray([10, 0, 0, 0, 65, 66]))
	_check(bad_huge.is_empty() and bad_neg.is_empty() and bad_short.is_empty() and bad_trunc.is_empty(),
		"G-28a: malformed identity packet lengths return empty without crashing or allocating")

func _test_string_schema_length_guards() -> void:
	var schema: NetworkSchemaSerializer = NetworkSchemas.string()
	var enc := StreamPeerBuffer.new()
	schema.encode("hello-netfox", enc)
	var dec := StreamPeerBuffer.new()
	dec.data_array = enc.data_array
	_check(str(schema.decode(dec)) == "hello-netfox", "G-28b: NetworkSchemas.string() round-trips cleanly")

	var bad := StreamPeerBuffer.new()
	bad.data_array = PackedByteArray([0xff, 0xff, 0xff, 0x7f])
	_check(str(schema.decode(bad)) == "", "G-28b: NetworkSchemas.string().decode ignores 0x7fffffff length without SIGBUS")

func _test_identity_server_packet_size_cap() -> void:
	var cmd := _NetworkCommandServer.new()
	var id_srv := _NetworkIdentityServer.new(cmd)
	var dummy := Node.new()
	dummy.name = "G28CapProbe"
	add_child(dummy)
	id_srv.register_node(dummy)
	var path: String = str(dummy.get_path())
	var ser := _IdentityPacketSerializer.new()
	var payload: PackedByteArray = ser.serialize({path: 99})
	# Pad past max_incoming_packet_size (16384 bytes) with valid zero entries.
	var padded := PackedByteArray()
	padded.append_array(payload)
	var extra := PackedByteArray()
	extra.resize(20000)
	extra.fill(0)
	padded.append_array(extra)
	id_srv._handle_ids(2, padded)
	var ident: _NetworkIdentifier = id_srv._get_identifier_of(dummy)
	_check(ident != null and not ident.has_id_for(2),
		"G-28c: oversized identity packet (>16 KB) is dropped before recording ids")
	dummy.free()
	id_srv.free()
	cmd.free()

func _test_command_transport_truncated_prefix() -> void:
	var cmd := _NetworkCommandServer.new()
	var fired: Array[int] = [0]
	cmd.register_command(func(_sender: int, _data: PackedByteArray) -> void: fired[0] += 1)
	cmd._packet_transport.on_receive.connect(cmd._handle_command)
	# Exact 3-byte prefix "\0nf" with no command index byte must not dispatch command #0.
	cmd._packet_transport._handle_packet(2, PackedByteArray([0, 78, 70]))
	_check(fired[0] == 0, "G-29: 3-byte raw prefix without command index byte does not dispatch command #0")
	cmd.free()
