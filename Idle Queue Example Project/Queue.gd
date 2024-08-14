class_name Queue
## Basic queue class.
##
## This class acts as a simple queue data structure made from an [Array] that
## does not reindex all parameters when the front value is removed. This
## means that the front value of the queue can be quickly removed from the
## list even when the queue gets very large.

## The maximum size of array containing the values of the queue.
## Also the maximum number values that can be stored in the queue.
const MAX_SIZE : int = 2147483647

# The array containing the values of the queue.
var _list : Array

# The array index of the first value in the queue.
var _front : int = 0

# The array index of the last value in the queue.
# This will be -1 when the queue is empty.
var _back : int = -1

## [param initial_size]: The starting size of the array containing the values
## of the queue. (Every time the array is resized, values have to be reindexed,
## and can be slow when the queue gets very large. If you know that the queue
## is going to be very large, setting this value to a larger number will
## avoid resizing the array many times as the queue gets larger.)
func _init(initial_size:int = 64):
	assert(initial_size > 0, "Error: Queue size must be greater than zero.")
	_list = []
	_list.resize(initial_size)


## Pushes value to the back of the queue.
## [param val]: The value to push.
func push(val) -> int:
	if is_empty():
		_back = _front
		_list[_front] = val
		return OK
	
	if size() == _list.size():
		if not _resize_list(_list.size() * 2):
			push_error("Queue has reached max size. Cannot push new entry.")
			return ERR_OUT_OF_MEMORY
		_back += 1
		_list[_back] = val
		return OK
	
	_back += 1
	
	# Wrap back around to front
	if _back >= _list.size():
		_back = 0
	
	_list[_back] = val
	
	return OK


func push_batch(vals:Array) -> int:
	if vals.is_empty():
		return OK
	
	var new_size := size() + vals.size()
	
	if new_size > MAX_SIZE:
		push_error("Pushing list would exceed the max queue size.")
		return ERR_PARAMETER_RANGE_ERROR
	
	# replace _list with vals
	if is_empty():
		vals = vals.duplicate()
		var vals_size := vals.size()
		if _list.size() > vals_size:
			vals.resize(_list.size())
		
		_list = vals
		_back = vals_size - 1
		_front = 0
		return OK
	
	var new_list_size = _list.size()
	while new_list_size < new_size:
		new_list_size *= 2
		
		if new_list_size > MAX_SIZE:
			new_list_size = MAX_SIZE
			break
	
	_resize_list(size())
	_list = _list + vals
	_back = _list.size() - 1
	_list.resize(new_list_size)
	
	return OK


## Returns the front entry in the queue without removing it.
func peek():
	if is_empty():
		return null
		
	return _list[_front]


func peek_batch(count:int) -> Array:
	assert(count >= 0, "Count parameter must be greater than or equal to 0.")
	
	return to_array().slice(0, count)


## Removes and returns the front entry in the queue.
func pop():
	if is_empty():
		return null
	
	var ret_val = _list[_front]
	_list[_front] = null
	
	# if the size is one set the front back to 0 and the back to null (-1)
	if _front == _back:
		_front = 0
		_back = -1
		return ret_val
	
	_front += 1
	
	if _front >= _list.size():
		_front = 0
	
	return ret_val


func pop_batch(count:int) -> Array:
	assert(count >= 0, "Count parameter must be greater than or equal to 0.")
	
	var arr = to_array()
	var list_size = _list.size()
	
	_front = 0
	
	if count < arr.size():
		_list = arr.slice(count)
		_back = _list.size() - 1
	else:
		_list = []
		_back = -1
	
	_list.resize(list_size)
	
	return arr.slice(0, count)
	
	



## Empties the queue.
## [param size]: The size to make the array containing the values of the queue.
## By default this value is the current size of the array.
func clear(_size:int=_list.size()) -> void:
	_init(_size)
	_front = 0
	_back = -1


## Checks if the queue is empty.
func is_empty() -> bool:
	return _back == -1


## Returns the number of entries in the queue.
func size() -> int:
	if is_empty():
		return 0
	
	if _back < _front:
		return _back + 1 + (_list.size() - _front)
	else:
		return _back - _front + 1


## Returns the value at the given index in the queue without removing it.
## [param index]: The index of the value in the queue.
## [allow_out_of_bounds]: If true, this function will return null instead of
## throwing an error if index is outside of the bounds of the queue.
func get_value(index:int, allow_out_of_bounds:=false):
	
	var out_of_bounds := index < 0 or index >= size()
	
	assert(not (out_of_bounds and not allow_out_of_bounds),  "Index %s is out of bounds." % index)
	if out_of_bounds:
		return null
	
	var array_index = _front + index
	if array_index >= _list.size():
		array_index -= _list.size()
	
	return _list[array_index]


func replace(index:int, val, allow_out_of_bounds:=false) -> bool:
	var out_of_bounds := index < 0 or index >= size()
	assert(not (out_of_bounds and not allow_out_of_bounds),  "Index %s is out of bounds." % index)
	if out_of_bounds:
		return false
	
	var array_index = _front + index
	if array_index >= _list.size():
		array_index -= _list.size()
	
	_list[array_index] = val
	
	return true


## Returns an array containing all the values in the queue.
func to_array() -> Array:
	if is_empty():
		return []
	
	if _front <= _back:
		return _list.slice(_front, _back + 1)
	else:
		return _list.slice(_front) + _list.slice(0, _back + 1)


func _resize_list(new_size:int) -> bool:
	
	if is_empty() or (_front <= _back and new_size > _back):
		_list.resize(new_size)
		return true
	
	var _size := size()
	
	if new_size < _size:
		return false
	
	if new_size >= MAX_SIZE:
		if _list.size() == MAX_SIZE:
			return false
		
		new_size = MAX_SIZE
	
	var vals := to_array()
	vals.resize(new_size)
	_list = vals
	_front = 0
	_back = _size - 1
	return true
