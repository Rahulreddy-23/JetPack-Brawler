extends RefCounted
class_name _IdentityPacketSerializer

# Serializes a set of (ID, full name) pairs
#
# Used by NetworkIdentityServer, when sending local IDs to other peers

# PATCH (see addons/NETFOX_PATCHES.md): the longest name an honest client sends, in
# bytes. Names are node paths, which in this project are ASCII.
const MAX_NAME_BYTES := 128

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
# PATCH: reads at most max_entries entries (all if max_entries is negative), so a
# caller that refuses a packet of more than N entries passes N + 1.
func deserialize(data: PackedByteArray, max_entries: int = -1) -> Dictionary:
	var ids := {}
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = data

	while buffer.get_available_bytes() > 0:
		if max_entries >= 0 and ids.size() >= max_entries:
			break
		# PATCH (see addons/NETFOX_PATCHES.md): get_utf8_string() allocates the length
		# the packet declares before it checks the bytes left, so 4 bytes declaring 2 GB
		# kill the process. Check the length first. A packet that is malformed or cut
		# anywhere registers nothing, not the entries before the bad one.
		if buffer.get_available_bytes() < 4:
			return {}
		var name_size := buffer.get_32()
		if name_size < 0 or name_size > buffer.get_available_bytes():
			return {}
		# PATCH: the engine prints an error line for every invalid UTF-8 byte it decodes,
		# so a name of 14,000 bytes of 0xff costs 14,000 lines and half a second. A name
		# is refused, with its packet, if it is longer than MAX_NAME_BYTES or has a byte
		# of 0x80 or more, judged on the raw bytes before they are decoded. Names are node
		# paths and this project's are ASCII: a node named with other characters would
		# not be synchronised.
		if name_size > MAX_NAME_BYTES:
			return {}
		var raw := buffer.get_data(name_size)[1] as PackedByteArray
		for byte in raw:
			if byte >= 0x80:
				return {}
		var full_name := raw.get_string_from_ascii()

		# The id is a varuint that must end inside the packet
		var id := 0
		var id_complete := false
		for i in 10:
			if buffer.get_available_bytes() == 0:
				break
			var byte := buffer.get_u8()
			id += (byte & 0x7f) << (i * 7)
			if byte & 0x80 == 0:
				id_complete = true
				break
		if not id_complete:
			return {}

		ids[full_name] = id

	return ids
