extends Node3D
## The level, before anything else looks at it: VaultBuster's shelf layout out, and as deep as the library needs (level.gd).

func _ready() -> void:
	Level.strip(self)
	Level.stretch(self)
