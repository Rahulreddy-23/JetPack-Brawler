extends Node
## Regression test for active unmerged geminiceo fix (G-31) against origin/main (cf9c87a).
## Fails on origin/main without the fix (decodes 15,000 non-ASCII bytes and prints 15,000
## Unicode parsing error lines per packet).
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
	_test_cstring_netref_ascii_and_length_guard()
	print("%d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

func _test_cstring_netref_ascii_and_length_guard() -> void:
	var netref: NetworkSchemaSerializer = NetworkSchemas._netref()
	# Valid ASCII node path round-trips cleanly.
	var valid_buf := StreamPeerBuffer.new()
	netref.encode(_NetworkIdentityReference.of_full_name("/root/Main/Bots/Bot1/Input"), valid_buf)
	var read_valid := StreamPeerBuffer.new()
	read_valid.data_array = valid_buf.data_array
	var ok_ref: _NetworkIdentityReference = netref.decode(read_valid) as _NetworkIdentityReference
	_check(ok_ref != null and not ok_ref.has_id() and ok_ref.get_full_name() == "/root/Main/Bots/Bot1/Input",
		"G-31: valid ASCII identity reference round-trips cleanly")

	# Crafted rollback input frame: id=0 + 15,000 bytes of 0xff + NUL (15,000 Unicode errors on unpatched main).
	var raw := PackedByteArray()
	raw.append(0)
	for _i: int in 15000:
		raw.append(0xff)
	raw.append(0)
	var bad_buf := StreamPeerBuffer.new()
	bad_buf.data_array = raw
	var bad_ref: _NetworkIdentityReference = netref.decode(bad_buf) as _NetworkIdentityReference
	_check(bad_ref != null and bad_ref.get_full_name() == "" and bad_buf.get_available_bytes() == 0,
		"G-31: non-ASCII c_string identity reference is rejected without Unicode log flood (len=%d)" % bad_ref.get_full_name().length())

	# Overlong ASCII name (>128 bytes) is also rejected without growing unboundedly.
	var long_raw := PackedByteArray()
	long_raw.append(0)
	for _i: int in 300:
		long_raw.append(65)
	long_raw.append(0)
	var long_buf := StreamPeerBuffer.new()
	long_buf.data_array = long_raw
	var long_ref: _NetworkIdentityReference = netref.decode(long_buf) as _NetworkIdentityReference
	_check(long_ref != null and long_ref.get_full_name() == "" and long_buf.get_available_bytes() == 0,
		"G-31: overlong ASCII c_string identity reference (>128 bytes) is rejected cleanly")
