extends Node2D

## Function that simulates a function that will take a 
## predictable amount of time to process.
func constant_function(n:=1.0) -> void:
	var num : float = 9_223_372_036_854_775_807.0
	for i in range(int(10000 * n)):
		num = sqrt(num)

func const_1():
	constant_function(0.5)
	print("Constant 1 complete.")

func const_2():
	constant_function(1)
	print("Constant 2 complete.")

func const_3():
	constant_function(1.5)
	print("Constant 3 complete.")

## Function simulates a complicated function that will take 
## an unknown amount of time to process.
func complex_function(n:=1.0) -> void:
	
	var num : float = 9_223_372_036_854_775_807.0
	for i in range(int((randi() % 10000) * n)):
		num = sqrt(num)
	
	print("Complex function complete.")


func _process(_delta):
	
	# Simulate main game and physics processes
	#complex_function(25)
	
	if Input.is_action_pressed("1"):
		
		# Call complex_function x 500 without IdleQueue (very jittery).
		for i in range(500):
			complex_function(1)
	
	if Input.is_action_pressed("2"):
		
		# Call complex_function x 500 over multiple frames using IdleQueue.
		for i in range(500):
			# Add complex_func to the idle queue with 1 as the parameter.
			IdleQueue.add_task(complex_function.bind(1))
	
	if Input.is_action_pressed("3"):
		
		var queue_id := 0
		var ordered := false
		
		# Add multiple tasks of varying complexity.
		for i in range(500):
			# These will be completed out of order unless ordered is true.
			IdleQueue.add_task(const_1, queue_id, ordered)
			IdleQueue.add_task(const_2, queue_id, ordered)
			IdleQueue.add_task(const_3, queue_id, ordered)
