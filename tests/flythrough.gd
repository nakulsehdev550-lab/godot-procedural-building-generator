extends Node3D
## Movie flythrough: orbits the demo buildings. Run:
##   xvfb-run godot --path . --rendering-driver opengl3 --write-movie movie/frame.png --fixed-fps 30 res://demo/demo_house.tscn --script? 
## (we instead add ourselves via a wrapper scene; see run_movie.sh)
var t := 0.0
var cam: Camera3D
var radius := 26.0
var height := 11.0
func _ready() -> void:
	cam = Camera3D.new()
	add_child(cam)
	cam.current = true
func _process(delta: float) -> void:
	t += delta
	var a := t * 0.35
	cam.position = Vector3(cos(a) * radius, height + sin(t * 0.5) * 2.0, sin(a) * radius)
	cam.look_at(Vector3(0, 5, 0))
