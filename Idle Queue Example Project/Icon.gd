extends Sprite2D

@export var rot_speed : float = 0.75

func _process(delta):
	rotate(delta * rot_speed)
