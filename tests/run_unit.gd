extends SceneTree
# DREADPULSE Phase 0 단위 검증 러너.
# 실행: & $godot --headless --path . --script res://tests/run_unit.gd

const Catalog := preload("res://sim/parts_catalog.gd")

var _pass := 0
var _fail := 0

func _init() -> void:
	_run_all()
	print("unit result: %d passed / %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func _run_all() -> void:
	_test_harness()
	_test_catalog()

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: " + label)

func _test_harness() -> void:
	check(true, "harness boots")

func _test_catalog() -> void:
	var b := Catalog.get_def("boiler")
	check(not b.is_empty(), "boiler exists")
	check(b.kind == "steel" and int(b.required_charge) == 2, "boiler def fields")
	var adr := Catalog.get_def("main_turret", "nerve")
	check(adr.name == "아드레날린 포", "graft substitutes name")
	var has_adr := false
	for e in adr.effects:
		if int(e.type) == Catalog.Effect.INTERVAL_REDUCE_ON_HIT:
			has_adr = true
	check(has_adr, "adrenaline effect present")
	check(Catalog.get_def("no_such_part").is_empty(), "unknown type -> empty")
	check(Catalog.get_def("autoloader", "nerve").is_empty(), "invalid graft -> empty")
	for t in Catalog.PARTS:
		var d: Dictionary = Catalog.PARTS[t]
		check(d.has("kind") and d.has("hull") and d.has("effects"), "part %s complete" % t)
