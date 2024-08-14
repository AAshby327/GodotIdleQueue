extends Label

func _process(_delta):
	
	# Update fps:
	text = "FPS: " + str(Engine.get_frames_per_second())
