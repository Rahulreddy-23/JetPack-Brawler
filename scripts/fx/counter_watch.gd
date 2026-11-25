class_name CounterWatch
extends RefCounted
## The high-water marks of the counters of one node (architecture D7). A counter in rollback
## state only rises in the settled history, but while the netcode re-simulates and corrects, a
## value seen on screen can briefly go down and come back. The mark is the highest value seen:
## step() reports an increase only above it, so a drop and a return to the same value report
## nothing, and a drop followed by a rise above the mark reports only the part above it.
## The first value seen for a counter is recorded and reports nothing. The caller only steps a
## node once its counters come from real state, so a node that appears late does not replay
## its past. Presentation only; it reads numbers and holds its own.

## Mark of a counter that has not been seen yet. Real counters are never negative.
const UNSEEN: int = -1

## The director's loop count at the moment it first found this node's state to be real, or -1.
var armed_at_loop: int = -1

var _marks: PackedInt64Array = PackedInt64Array()

func _init(counter_count: int) -> void:
	_marks.resize(counter_count)
	_marks.fill(UNSEEN)

## Compares a counter with its mark and returns how far it rose above it (0 for no event).
func step(index: int, value: int) -> int:
	if index < 0 or index >= _marks.size() or value < 0:
		return 0
	var mark: int = _marks[index]
	if mark == UNSEEN:
		_marks[index] = value
		return 0
	if value <= mark:
		return 0
	_marks[index] = value
	return value - mark

## The highest value seen for a counter, or UNSEEN.
func mark(index: int) -> int:
	if index < 0 or index >= _marks.size():
		return UNSEEN
	return _marks[index]
