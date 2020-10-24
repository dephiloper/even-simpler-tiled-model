extends Node2D

func _ready() -> void:
	$Camera2D.position =+ Vector2(64 * 20, 64 * 20) / 2
