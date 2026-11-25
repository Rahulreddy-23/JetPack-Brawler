extends RefCounted
class_name _PeerRateLimit

# PATCH (see addons/NETFOX_PATCHES.md): lets a log line about what a peer sent
# through at most once per interval per peer, the first one always, so a peer
# cannot fill the log and spend the host's time on printing by repeating a bad
# packet. A user of this class erases a peer when it leaves and clears on reset.

const INTERVAL_MSEC := 1000

var _last_msec := {} # peer to the time (msec) of its last line

## True if a line about [param peer] may be logged now, and records that it was
func allow(peer: int) -> bool:
	var now := Time.get_ticks_msec()
	if now - (_last_msec.get(peer, -INTERVAL_MSEC) as int) < INTERVAL_MSEC:
		return false
	_last_msec[peer] = now
	return true

func erase_peer(peer: int) -> void:
	_last_msec.erase(peer)

func clear() -> void:
	_last_msec.clear()
