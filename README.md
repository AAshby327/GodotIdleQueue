# GodotIdleQueue
## What is it?
This is a simple GDscript godot plugin that allows processes to run between frames on the main thread.

The idle queue is a system that is designed to call functions over time on the main thread, prioritizing the _process and _physics_process functions for the scene tree as well as preventing frame rate jitter. Say you have a `my_func()` that needs to be called frequently in your game. Due to the function's complexity, every time it is called, the game begins to jitter and the frame rate momentarily drops. Normally the solution to this would be to call this function on a separate thread so that the main loop is not halted every time `my_func()` is called. This is not always viable because multithreaded functions are very limited in the godot engine (they cannot manipulate the scene tree or instantiate complex scenes). This script offers a solution to this problem. 

## How it works

The plugin adds a singleton that adds callables to a list that the engine will periodically work on while the main thread is idle. "Idle time" occurs after the main loop has executed all _process and _physics_process functions in the scene tree, but before the next frame begins. Normally the engine will just remain idle until it is time to start the next frame according to the set frame rate. The idle queue uses this time to call functions from the list. This functions similar to the `call_deferred()` method, the difference being that `call_deferred()` will call all functions that were deferred each frame, meaning that deferring too many functions using `call_deferred()` will cause the frame rate to stutter. The idle queue will call as many functions as possible during idle time until it is time for the next frame to start, where it will wait until the main thread is idle during the next frame to continue working on the list of callables. This will ensure your game will run main and physics processes smoothly while your complex lower priority functions will run in the background. 

While this program does not use multithreading, it supports working in tandem with multiple threads. Like, `call_deferred()` callables can be queued from non-main threads for further optimization.

## Use cases
* __Single-Threaded Games:__ Ideal for games that prioritize simplicity and want to avoid the complexities of multi-threaded programming.
* __Simulation Games:__ Optimizing AI, Rendering, and/or procedural generation processes.

## Adding the plugin to your project

1. Download a copy of the IdleQueue plugin via github
2. Copy the folder `godot_idle_queue_gd` and all of its contents into your project `res://addons` directory. (If your project does not have an addons folder, just create a folder and name it "addons").

If you did it correctly, you should see that "IdleQueue" is registered as an autoload under Project>Project Settings>Autoload, and you can access the singleton members using the keyword "IdleQueue".

Alternatively, you can just create and paste GodotIdleQueue://addons/godot_idle_queue_gd/IdleQueue.gd into your project and then manually register the script as an autoload.

## The basics

### Queueing a function call

To queue a function to be run during idle time, use the `add_task()` method:
```gdscript
# Queueing 'my_func()'
IdleQueue.add_task(my_func)
```

If you want to add parameters to the queued function, use the `Callable.bind()` method:
```gdscript
# Calls my_func(1) during idle time.
IdleQueue.add_task(my_func.bind(1))
```

To add a large amount of callables all at once, use the `add_task_array()` method:
```gdscript
var callables = []
for i in range(500):
  callables.append(my_func.bind(i))

IdleQueue.add_task_array(callables)
# This will be much faster than adding all callables individually using add_task() especially if your
# game uses multiple threads because a mutex is locked every time an add_task is called, but only once in add_task_array.
# If your game does not use multithreading, don't worry about this.
```

### System parameters
* __frame_padding_usec:__ The amount of time (in microseconds) to give between ending idle processing and the start of the next frame. This gives idle calls time to finish without going over the given amount of time per frame.
* __min_process_time_usec:__ The minimum amount of time (in microseconds) the singleton must spend processing queued calls each frame. This prevents the idle processing from being completely halted if other processes are taking up too much time between frames. __NOTE:__ If `Engine.max_fps` is set to 0, the singleton will only process callables for the minimum amount of time each frame, so if this is the case, make sure min_process_time_usec is greater than 0.
* __baseline_estimate_usec:__ The amount of time (in microseconds) the singleton will set aside to process a function that has not been queued before.

### Best practices
It is better to break up more complex functions into smaller ones, because once the IdleQueue starts executing a function, it does not stop until it is complete. If you use smaller functions, It is then possible to stop execution of a task and pick up where it left off during the next frame, making it less likely that the function will take more time than is available in a given frame.
For example:
```gdscript
# Instead of this:
func complicated_func():
  for i in range(500):
    my_func(i)

func _ready():
  IdleQueue.add_task(complicated_func)

# Do this:
func _ready():
  for i in range(500):
    IdleQueue.add_task(my_func(i))
```

## Multiple queues
For more advanced applications it can be useful to create multiple queues. These separate queues can be used to group calls for separate overarching tasks (ei. A queue for the AI and one for rendering, or a separate queue for each chunk when loading an open world). These queues can be dynamically prioritized, paused, or canceled, allowing for further optimization for the IdleQueue.

### Creating a new queue:
```gdscript
var queue_id = IdleQueue.create_queue()
```
The returned value of IdleQueue.create_queue() is an integer that represents the newly created queue's id. This is then used to reference and manipulate its corresponding queue.

To enqueue callables on this new queue, specify the queue_id in the `add_task()` method:
```gdscript
# Add my_func to new queue
IdleQueue.add_task(my_func, queue_id)
```

### Setting the priority
Each queue is given a priority in the form of an integer. At the start of idle time each frame, the system will call functions from the (unpaused) queue of the greatest priority value. Once finished, the system will then call from the queue of the next highest priority, and so on. 

To set the priority of a queue:
```gdscript
# This will set the queue of id queue_id to 5. It will be processed before all queues of priority less than 5.
IdleQueue.set_queue_priority(queue_id, 5)
```

A queue's priority can be set at any time, allowing for dynamic ordering of tasks.

### Pausing queues
When a queue is paused, the system will not process the callables within it until the queue is unpaused.
```gdscript
# Pause the queue
IdleQueue.pause_queue(queue_id)

# Unpause the queue
IdleQueue.unpause_queue(queue_id)
```

### Locking queues
You may encounter processes that will require a finite number of function calls to complete and once the process is finished you no longer need the queue that the process used. For this, once the final callable has been enqueued to this queue, the queue can be locked. This will prevent any more callables to be enqueued to this queue and once the queue is completely processed, the queue is then deleted.
```gdscript
var finite_queue = IdleQueue.create_queue()

for i in range(50):
  IdleQueue.add_task(my_func.bind(i), finite_queue)

IdleQueue.lock_queue(finite_queue)
# The IdleQueue will now delete the new 'finite_queue' once all 50 queued callables are processed.

# This will throw an error
IdleQueue.add_task(my_func.bind(5))
```

### Canceling queues
If you want to cancel a queue, you can clear all queued tasks within a given queue using:
```gdscript
IdleQueue.cancel_queue(queue_id)
```
If the queue being canceled is locked, the queue will also be deleted.

### The default queue
If no queue_id is given in the `add_task()` or `add_task_array()` methods, the given task(s) will be enqueued in the default queue. This is a special queue that will always be present and cannot be locked. This queue is meant to keep miscellaneous tasks that do not need to be actively managed via a separate queue, or if you just don't want to deal with managing separate queues.

The default queue's id is given by `IdleQueue.DEFAULT_QUEUE_ID`.

## Execution order

The idle queue keeps track of how long each function takes to execute in order to predict how likely a function is to exceed the amount of idle time remaining during the current thread. This means that if the IdleQueue is processing callables and comes across a function that will take longer than the frame rate has time for, it will move on to a task that will take less time in order to make the most of the remaining idle time. Sometimes however, you may need callables to be executed in the order that they are enqueued. To do this, set the `ordered` parameter in the `add_task()` method to true.
```gdscript

func print_num(num):
  print(num)

IdleQueue.add_task(print_num.bind(1), queue_id, true)
IdleQueue.add_task(print_num.bind(2), queue_id, true)
IdleQueue.add_task(print_num.bind(3), queue_id, true)

IdleQueue.add_task_array([print_num.bind(4), print_num.bind(5)], queue_id, true)

IdleQueue.add_task(print_num.bind(6), queue_id, true)

# This will always output 1, 2, 3, 4, 5, 6
```

# More
For further information regarding the members of the Idle Queue plugin, refer to the documentation comments provided in GodotIdleQueue://addons/godot_idle_queue_gd/IdleQueue.gd.
