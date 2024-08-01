"""MIT License

Copyright (c) 2024 Andrew Ashby

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"""

class_name IdleQueueSingleton extends Node
## Signleton script that will process methods during idle time on the main thread.
##
## The IdleQueue signleton places callables in a queue to be executed when the 
## cpu is not busy, prioritizing the physics and main processes of the game
## with minimal effect on the frame rate. This allows methods to be run in the 
## background on the main thread. (All member functions of this singleton are 
## thread safe). 
## [br][br]
## Every frame, the Godot Engine will call the [method Node._physics_process] 
## and [method Node._process] functions for every node in the scene tree. 
## Once every node has been processed, the engine will stay idle, and wait for
## the next frame to start. The IdleQueue uses this time where the main thread 
## would normally be idle to process queued callables until the next frame begins.
## [br][br]
## Some games however, will have less idle time to work with than others, 
## whether it is because the node processing takes up most of the frame time,
## or if the frame rate is unlimited. Less idle time will mean that the queued
## methods will take longer to process. To counteract this, 
## [member min_process_time_usec] can be used to ensure that the singleton 
## processes queued calls for a given amount of time each frame. The exchange
## for faster idle processing is a decrease in frame rate during times of 
## increased physics and or main processing times.
## [br][br]
## [b]Queues:[/b] Callables can be enqueued into separate queues which act as
## separate groups of tasks that can be prioritized, paused, or canceled. 
## A queue can be created using [method create_queue]. This function will 
## return the queue's id as an integer. This id can then be used to interact
## with the queue through this signleton. Each queue has a priority represented
## as an integer (this can be set by using [method set_queue_priority]). Each 
## frame, the singleton will process the (unpaused) queue with the highest 
## priority value. Once complete, the singleton will move on to the queue
## of the next highest value, and so on. [br]
## Queues can also be locked. Once locked, queues will no longer be able to 
## recieve more callables, and the queue will be deleted after it is completed
## or canceled. This can be useful for grouping a limited set of callables 
## that are all part of the same overarching task, that will be discarded once
## the task if complete.
## [br][br]
## [b]The Default Queue:[/b] The singleton has a queue that cannot be locked
## or deleted that can be accessed using [member DEFAULT_QUEUE_ID]. This acts as
## a simple queue for any callables that do not need a completely separate 
## queue, or you can just use the defualt queue for all callables if you just 
## don't want deal with managing queues.
## [br][br]
## [b]Best Practices:[/b] [br]
## It is optimal to separate larger functions into sets of smaller tasks when 
## adding them to a queue. This is because once a queued callable is executed,
## it does not stop until the method is finished. If the method takes longer 
## to execute than the frame rate has time for, it will cause lag. As an example:
## [codeblock]
## # Instead of:
## func my_func():
##     for i in range(500):
##         my_other_func(i)
##
## func _ready():
##     IdleQueue.add_task(my_func)
##
## # Do this:
## func _ready():
##     for i in range(500):
##         IdleQueue.add_task(my_other_func.bind(i))
## [/codeblock]


## Emitted when all nodes have finished processing (including idle processing).
signal process_end

## The queue id of the default queue.
const DEFAULT_QUEUE_ID := 0

## The amount of time (in microseconds) to give between ending idle processing
## and the start of the next frame. This gives idle calls time to finish 
## without going over the given amount of time per frame.
@export var frame_padding_usec : int = 500

## The minimum amount of time (in microseconds) the singleton must spend processing
## queued calls each frame. This prevents the idle processing from being completely
## haulted if other processes are taking up too much the time between frames.
@export var min_process_time_usec : int = 0

## The amount of time (in microseconds) the singleton will set aside to process
## a function that has not been queued before.
@export var baseline_estimate_usec : int = 1000

var _next_queue_id := 1
var _queue_dict : Dictionary
var _current_queue : TaskQueue = null

var _frame_time_usec : int
var _first_physics_tick := true
var _frame_start_usec : int
var _idle_process_start : int
var _processing := false

var _total_call_times_usec : Dictionary
var _total_call_counts : Dictionary

var _mutex := Mutex.new()

func _ready():
	# Create default queue
	_queue_dict[DEFAULT_QUEUE_ID] = TaskQueue.new(DEFAULT_QUEUE_ID, 0)
	
	get_tree().physics_frame.connect(_start_frame_timer)
	
	update_fps()

# _process for this node will be called after all other nodes and will run until
# the time budget for each frame has been reached.
func _process(delta):
	_processing = true
	_idle_process_start = Time.get_ticks_usec()
	
	var calls := 0
	
	if _get_highest_priority_queue() and \
	# Don't make calls if frame rate is starting to decrease
	(_frame_time_usec == 0 or int(delta * 1000000) <= _frame_time_usec):
		
		var next_task := _current_queue.first
		
		while not _is_over_budget():
			var call_start := Time.get_ticks_usec()
			
			if next_task.callable.is_valid():
				
				# Get average call time of the next task
				var function_name := next_task.callable.get_method() as StringName
				if not _total_call_counts.has(function_name):
					_total_call_counts[function_name] = 0
					_total_call_times_usec[function_name] = 0
				
				var average_call_time = baseline_estimate_usec
				if _total_call_counts[function_name] != 0:
					average_call_time = _total_call_times_usec[function_name] / _total_call_counts[function_name]
				
				# Find easier unordered task if the current task will take too long
				if _is_over_budget(call_start + average_call_time*2) and calls > 0:
					
					while next_task != null and next_task.callable.get_method() == function_name:
						next_task = _get_next_unordered_task(next_task)
					
					if next_task == null: break
					else: continue
				
				next_task.callable.call()
				
				calls += 1
				_total_call_counts[function_name] += 1
				_total_call_times_usec[function_name] += Time.get_ticks_usec() - call_start
				
			var to_remove := next_task
			
			if next_task != _current_queue.first:
				next_task = _get_next_unordered_task(next_task)
			else:
				next_task = next_task.next_task
			
			_mutex.lock()
			_current_queue.remove(to_remove)
			to_remove = null
			_mutex.unlock()
			
			if _current_queue.first == null:
				
				if _current_queue.completion_task.is_valid():
					_current_queue.completion_task.call()
				
				if _current_queue.locked:
					_mutex.lock()
					_queue_dict.erase(_current_queue.id)
					_mutex.unlock()
					
					_current_queue.free()
				
				if not _get_highest_priority_queue():
					break
				
				next_task = _current_queue.first
				continue
			
			if next_task == null:
				break
	
	_processing = false
	_first_physics_tick = true
	
	process_end.emit()


## Updates the frame timer to match the engine frame rate.
## Call this function whenever [member Engine.max_fps] is changed.
func update_fps() -> void:
	if Engine.max_fps > 0:
		_frame_time_usec = int(1000000.0 / Engine.max_fps)
	else:
		_frame_time_usec = 0;


## Checks if tasks from the IdleQueue are currently being excecuted.
func is_processing_tasks() -> bool:
	return _processing


## Creates a new queue.
## [param priority]: The queue priority. (Higher priority queues are processed first)
## [param start_on_creation]: Whether or not to start (unpause) the queue after creating the queue.
## Returns the queue id to reference when manipulating this new queue.
func create_queue(priority := 0, start_on_creation := true) -> int:
	var new_queue = TaskQueue.new(_next_queue_id, priority)
	new_queue.paused = not start_on_creation
	
	_mutex.lock()
	_next_queue_id += 1
	_queue_dict[new_queue.id] = new_queue
	_mutex.unlock()
	
	return new_queue.id


## Checks if a queue of a given id exists.
## [param queue_id]: The id to check.
func queue_exists(queue_id:int) -> bool:
	return _queue_dict.has(queue_id)


## Adds a single task to a given queue (Return values will be ignored).
## [param callable]: The task (in the form of a callable) to enqueue in the queue.
## [param queue_id]: The id of the queue to add the task to (given by create_queue()).
## [param ordered]: Whether or not the task must be completed the order that the 
## task was queued with respect to other ordered tasks in the given queue.
func add_task(callable:Callable, queue_id:=DEFAULT_QUEUE_ID, ordered:=false) -> Error:
	var queue := _queue_dict.get(queue_id) as TaskQueue
	
	if queue == null:
		push_error("Queue with id %s does not exist." % queue_id)
		return ERR_DOES_NOT_EXIST
	
	if queue.locked:
		push_error("Queue with id %s is locked and new tasks cannot be added." % queue_id)
		return ERR_LOCKED
	
	var new_task = Task.new(callable, ordered)
	
	_mutex.lock()
	queue.add(new_task)
	_mutex.unlock()
	
	return OK


## Adds a batch of tasks to a queue.
## [param callables]: An array containing all tasks as callables to enqueue.
## [param queue_id]: The id of the queue to add the tasks to (given by create_queue()).
## [param ordered]: Whether or not the tasks must be completed the order that they
## appear in the array (callables).
func add_task_array(callables:Array, queue_id:=DEFAULT_QUEUE_ID, ordered:=false) -> Error:
	var queue := _queue_dict.get(queue_id) as TaskQueue
	
	if queue == null:
		push_error("Queue with id %s does not exist." % queue_id)
		return ERR_DOES_NOT_EXIST
	
	if queue.locked:
		push_error("Queue with id %s is locked and new tasks cannot be added." % queue_id)
		return ERR_LOCKED
	
	var list_start : Task = null
	var list_end : Task = null
	
	for item in callables:
		if not item is Callable: continue
		
		var new_task := Task.new(item, ordered)
		
		if list_start == null:
			list_start = new_task
			list_end = new_task
			continue
		
		list_end.next_task = new_task
		new_task.previous_task = list_end
		list_end = list_end.next_task
	
	if list_start != null:
		_mutex.lock()
		queue.add(list_start)
		_mutex.unlock()
	
	return OK

## Sets the priority for a given queue.
## [param queue_id]: The queue's id (given by create_queue()).
## [param priority]: The new priority for the queue.
func set_queue_priority(queue_id:int, priority:int) -> bool:
	if not _queue_dict.has(queue_id):
		return false
	
	_mutex.lock()
	_queue_dict[queue_id].priority = priority
	_mutex.unlock()
	return true


## Gets the priority of a given queue.
## [param queue_id]: The queue's id (given by create_queue()).
func get_queue_priority(queue_id:int) -> int:
	var queue := _queue_dict.get(queue_id) as TaskQueue
	
	if queue == null:
		push_error("Queue with id %s does not exist." % queue_id)
		return 0
	
	return queue.priority


## Gives a queue a task to call when the queue has completed all of its queued tasks.
## [param queue_id]: The id of the queue to add the task to (given by create_queue()).
## [param callable]: The method to call on completion.
func set_queue_completion_task(queue_id:int, callable:Callable) -> void:
	var queue := _queue_dict.get(queue_id) as TaskQueue
	
	if queue == null:
		push_error("Queue with id %s does not exist." % queue_id)
		return
	
	_mutex.lock()
	queue.completion_task = callable
	_mutex.unlock()


## Gives a queue a task to call if the queue is canceled.
## [param queue_id]: The id of the queue to add the task to (given by create_queue()).
## [param callable]: The method to call on cancelation.
func set_queue_cancel_task(queue_id:int, callable:Callable) -> void:
	var queue := _queue_dict.get(queue_id) as TaskQueue
	
	if queue == null:
		push_error("Queue with id %s does not exist." % queue_id)
		return
	
	_mutex.lock()
	queue.cancel_task = callable
	_mutex.unlock()


## Unpauses a queue.
## [param queue_id]: The id of the queue to unpause (given by create_queue()).
func start_queue(queue_id:int) -> void:
	var queue := _queue_dict.get(queue_id) as TaskQueue
	
	if queue == null:
		push_error("Queue with id %s does not exist." % queue_id)
		return
	
	_mutex.lock()
	queue.paused = false
	_mutex.unlock()


## Alias for start_queue().
## [param queue_id]: The id of the queue to unpause (given by create_queue()).
func unpause_queue(queue_id:int) -> void:
	start_queue(queue_id)


## Stops a queue from being processed until it is unpaused.
## [param queue_id]: The id of the queue to unpause (given by create_queue()).
func pause_queue(queue_id:int) -> void:
	var queue := _queue_dict.get(queue_id) as TaskQueue
	
	if queue == null:
		push_error("Queue with id %s does not exist." % queue_id)
		return
	
	_mutex.lock()
	queue.paused = true
	_mutex.unlock()


## Checks if a queue is paused.
## [param queue_id]: The id of the queue to unpause (given by create_queue()).
func is_queue_paused(queue_id:int) -> bool:
	var queue := _queue_dict.get(queue_id) as TaskQueue
	
	if queue == null:
		push_error("Queue with id %s does not exist." % queue_id)
		return false
	
	return queue.paused


## Locks a queue. Locked queues cannot recieve more tasks and will be deleted upon completion.
## [param queue_id]: The id of the queue to unpause (given by create_queue()).
func lock_queue(queue_id:int) -> Error:
	
	if queue_id == DEFAULT_QUEUE_ID:
		push_error("Default queue can not be locked.")
		return ERR_UNAVAILABLE
	
	var queue := _queue_dict.get(queue_id) as TaskQueue
	
	if queue == null:
		push_error("Queue with id %s does not exist." % queue_id)
		return ERR_DOES_NOT_EXIST
	
	_mutex.unlock()
	queue.locked = true
	_mutex.unlock()
	
	return OK


## Checks if a queue is locked.
## [param queue_id]: The id of the queue to unpause (given by create_queue()).
## Will return true if the queue does not exist.
func is_queue_locked(queue_id:int) -> bool:
	var queue := _queue_dict.get(queue_id) as TaskQueue
	
	if queue == null:
		return true
	
	return queue.locked


## Clears all tasks in a given queue. If the queue is locked, then the queue 
## will be deleted. If the queue has an execution task it will be executed.
## [param queue_id]: The id of the queue to unpause (given by create_queue()).
## [param delete_queue]: Whether or not the queue should be deleted.
## (Locked queues will be deleted regardless of this value).
func cancel_queue(queue_id:int, delete_queue:=false) -> Error:
	
	if queue_id == DEFAULT_QUEUE_ID and delete_queue:
		push_error("Default queue can not be deleted.")
		delete_queue = false
	
	var queue := _queue_dict.get(queue_id) as TaskQueue
	
	if queue == null:
		push_error("Queue with id %s does not exist." % queue_id)
		return ERR_DOES_NOT_EXIST
	
	if queue.cancel_task.is_valid():
		queue.cancel_task.call_deferred()
	
	_mutex.lock()
	queue.clear()
	if queue.locked or delete_queue:
		_queue_dict.erase(queue_id)
	_mutex.unlock()
	
	return OK

func _start_frame_timer() -> void:
	if _first_physics_tick:
		_frame_start_usec = Time.get_ticks_usec()
		_first_physics_tick = false
	
	var root := get_tree().root
	if get_index() != root.get_child_count() - 1:
		root.move_child(self, -1)

# Returns true if a given time is over the given process time bugeted to each frame.
func _is_over_budget(time_usec : int = Time.get_ticks_usec()):	
	if time_usec - _idle_process_start < min_process_time_usec:
		return false
	else:
		return time_usec - _frame_start_usec > _frame_time_usec - frame_padding_usec

# Puts the highest priority queue that is not paused or empty into _current_queue.
# Returns false if no queues are active (not empty or unpaused).
func _get_highest_priority_queue() -> bool:
	var highest : TaskQueue = null
	
	_mutex.lock()
	for entry in _queue_dict.values():
		
		if _is_over_budget():
			highest = null
			break
		
		var queue := entry as TaskQueue
		
		if queue.paused or queue.first == null:
			continue
		
		if highest == null:
			highest = queue
			continue
		
		if highest.priority < queue.priority:
			highest = queue

	_mutex.unlock()
	
	_current_queue = highest
	return highest != null

# Returns the next unordered task after a given task.
func _get_next_unordered_task(start : Task) -> Task:
	var task := start.next_task
	
	while task != null:
		if _is_over_budget():
			return null
		
		if not task.ordered:
			return task
		
		task = task.next_task
	
	return null


class Task:
	var callable : Callable
	var ordered : bool
	
	var previous_task : Task = null
	var next_task : Task = null
	
	func _init(_callable : Callable, _ordered : bool):
		callable = _callable
		ordered = _ordered

class TaskQueue:
	var id : int
	var priority : int = 0
	
	var first : Task = null
	var last : Task = null
	
	var locked := false
	var paused := false
	
	var completion_task : Callable
	var cancel_task : Callable
	
	func _init(_id : int, _priority : int):
		id = _id
		priority = _priority
	
	func add(task:Task) -> void:
		
		if first == null:
			first = task
			last = task
		else:
			last.next_task = task
			task.previous_task = last
		
		while last.next_task != null:
			last = last.next_task
	
	func remove(task:Task) -> void:
		
		if task.previous_task != null:
			task.previous_task.next_task = task.next_task
		
		if task.next_task != null:
			task.next_task.previous_task = task.previous_task
		
		if task == first:
			first = task.next_task
		
		if task == last:
			last = task.previous_task
	
	func clear() -> void:
		first = null
		last = null
