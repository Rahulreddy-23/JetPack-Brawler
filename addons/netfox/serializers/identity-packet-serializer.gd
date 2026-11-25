extends RefCounted
class_name _IdentityPacketSerializer

# Serializes a set of (ID, full name) pairs
#
# Used by NetworkIdentityServer, when sending local IDs to other peers

# ids: Dictionary[full_name, local_id]
func serialize(ids: Dictionary) -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	var varuint := NetworkSchemas.varuint()

	for full_name in ids.keys():
		var id := ids[full_name] as int

		buffer.put_utf8_string(full_name)
		varuint.encode(ids[full_name], buffer)

	return buffer.data_array

# return: Dictionary[full_name, local_id]
func deserialize(data: PackedByteArray) -> Dictionary:
	var ids := {}
	var varuint := NetworkSchemas.varuint()
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = data

	while buffer.get_available_bytes() > 0:
		# PATCH (geminiceo G-28): check the 4-byte length against remaining bytes before
		# allocating; Godot's StreamPeerBuffer.get_utf8_string(-1) allocates the declared
		# length first, so a 4-byte 0x7fffffff payload crashes the process with SIGBUS.
		if buffer.get_available_bytes() < 4:
			break
		var str_len := buffer.get_32()
		if str_len < 0 or str_len > buffer.get_available_bytes():
			break
		var full_name := ""
		if str_len > 0:
			var raw := buffer.get_data(str_len)
			if raw[0] != OK:
				break
			full_name = (raw[1] as PackedByteArray).get_string_from_utf8()
		if buffer.get_available_bytes() <= 0:
			break
		var id := varuint.decode(buffer) as int

		ids[full_name] = id

	return ids
