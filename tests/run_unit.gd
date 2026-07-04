extends SceneTree
# DREADPULSE Phase 0 단위 검증 러너.
# 실행: & $godot --headless --path . --script res://tests/run_unit.gd

var _pass := 0
var _fail := 0

func _init() -> void:
	_run_all()
	print("unit result: %d passed / %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func _run_all() -> void:
	_test_harness()

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: " + label)

func _test_harness() -> void:
	check(true, "harness boots")
