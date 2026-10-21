@tool
extends Node3D
## The one script a snapshot keeps (tools/snapshot.gd): the room shader's globals as they were when it was taken
## (the light zones' boxes, the daylight, the fog...), put back when it's opened, in the editor too. Only for as
## long as the editor's open: Project Settings > Shader Globals keeps its own.

@export var globals := {}


func _ready() -> void:
	for n: String in globals:
		RenderingServer.global_shader_parameter_set(n, globals[n])
