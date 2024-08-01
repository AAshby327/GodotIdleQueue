@tool
extends EditorPlugin

const AUTOLOAD_NAME = "IdleQueue"

func _enter_tree():
	add_autoload_singleton(AUTOLOAD_NAME, "res://addons/godot_idle_queue_gd/IdleQueue.gd")


func _exit_tree():
	remove_autoload_singleton(AUTOLOAD_NAME)
