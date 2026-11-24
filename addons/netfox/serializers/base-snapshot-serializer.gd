extends RefCounted
class_name _BaseSnapshotSerializer

var max_packet_size := 1440

var _identity_server: _NetworkIdentityServer
var _schemas: _NetworkSchema

# PATCH (see addons/NETFOX_PATCHES.md): peer to the time (msec) of its last warning
var _last_warning_msec := {}

static var _default_filter := func(subject: Object): return true
static var _logger := NetfoxLogger._for_netfox("DenseSnapshotSerializer")

func _init(p_schemas: _NetworkSchema, p_identity_server: _NetworkIdentityServer = null) -> void:
	assert(p_schemas != null, "Missing schemas!")
	# Intentionally storing reference, so it can be modified from the outside
	# e.g. RollbackSynchronizerServer adds a property
	_schemas = p_schemas
	_identity_server = p_identity_server

func _write_property(node: Node, property: NodePath, value: Variant, buffer: StreamPeerBuffer) -> void:
	_schemas.encode(node, property, value, buffer)

func _read_property(node: Node, property: NodePath, buffer: StreamPeerBuffer) -> Variant:
	return _schemas.decode(node, property, buffer)

func _write_identifier(subject: Object, peer: int, buffer: StreamPeerBuffer) -> Error:
	var netref := NetworkSchemas._netref()
	var identifier := _get_identity_server()._get_identifier_of(subject)
	if not identifier:
		_logger.error("Can't synchronize %s, identifier missing!", [subject])
		return ERR_DOES_NOT_EXIST

	var idref := identifier.reference_for(peer)
	netref.encode(idref, buffer)
	return OK

func _get_identity_server() -> _NetworkIdentityServer:
	if not _identity_server:
		_identity_server = NetworkIdentityServer
	return _identity_server

# PATCH (see addons/NETFOX_PATCHES.md): a warning about something a peer sent is
# logged at most once per second per peer, so a peer cannot fill the log, and
# spend the host's time on printing, by sending the same bad packet over and over
func _warn_peer(peer: int, text: String, values: Array = []) -> void:
	var now := Time.get_ticks_msec()
	if now - (_last_warning_msec.get(peer, -_WARNING_INTERVAL_MSEC) as int) < _WARNING_INTERVAL_MSEC:
		return
	_last_warning_msec[peer] = now
	_logger.warning(text, values)

const _WARNING_INTERVAL_MSEC := 1000
