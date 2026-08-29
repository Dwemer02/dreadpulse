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
		# 파싱 에러가 난 스크립트는 null이 아니라 인스턴스화 불가능한 GDScript로 돌아온다.
		# null만 걸러내면 아래 script.new()가 _init() 안에서 에러를 내고,
		# 그러면 quit()에 도달하지 못해 헤드리스 프로세스가 멈춘 채 남는다.
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			all_failures.append("%s :: 모듈을 로드할 수 없음 — 파싱 에러 (stderr 확인)" % path.get_file())
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
