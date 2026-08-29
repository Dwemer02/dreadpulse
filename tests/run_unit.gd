extends SceneTree
## 헤드리스 단위 테스트 러너.
## 실행: godot --headless --path . --script res://tests/run_unit.gd
## exit 0 = 전체 통과, exit 1 = 실패 있음.

const HELPERS_PATH := "res://tests/test_helpers.gd"

const MODULES: Array[String] = [
	"res://tests/unit/test_harness.gd",
	"res://tests/unit/test_sim_const.gd",
	"res://tests/unit/test_part_timing.gd",
]

func _init() -> void:
	var helpers_script: GDScript = load(HELPERS_PATH)
	var total_checks: int = 0
	var all_failures: Array[String] = []

	for path: String in MODULES:
		var script: GDScript = load(path)
		if script == null:
			all_failures.append("%s :: 모듈을 로드할 수 없음" % path)
			continue
		var module: RefCounted = script.new()
		var t: RefCounted = helpers_script.new()
		module.run(t)
		if not t.completed:
			all_failures.append("%s :: 모듈이 끝까지 실행되지 않았다 — run()이 중간에 중단됐다 (stderr 확인)" % path.get_file())
		total_checks += t.checks
		for failure: String in t.failures:
			all_failures.append("%s :: %s" % [path.get_file(), failure])

	print("")
	print("checks: %d, failures: %d" % [total_checks, all_failures.size()])
	for failure: String in all_failures:
		print("  FAIL  %s" % failure)
	if all_failures.is_empty():
		print("ALL PASS")
		quit(0)
	else:
		quit(1)
