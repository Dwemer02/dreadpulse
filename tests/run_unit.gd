extends SceneTree
## 헤드리스 단위 테스트 러너.
## 실행: godot --headless --path . --script res://tests/run_unit.gd
## exit 0 = 전체 통과, exit 1 = 실패 있음.

const HELPERS_PATH := "res://tests/test_helpers.gd"

const MODULES: Array[String] = [
	"res://tests/unit/test_harness.gd",
	"res://tests/unit/test_sim_const.gd",
	"res://tests/unit/test_part_timing.gd",
	"res://tests/unit/test_part_destruction.gd",
	"res://tests/unit/test_catalog.gd",
	"res://tests/unit/test_ship_state.gd",
	"res://tests/unit/test_build_loader.gd",
	"res://tests/unit/test_targeting.gd",
	"res://tests/unit/test_conditions.gd",
	"res://tests/unit/test_actions.gd",
	"res://tests/unit/test_trigger_engine.gd",
]

func _init() -> void:
	var helpers_script: GDScript = load(HELPERS_PATH)
	var total_checks: int = 0
	var all_failures: Array[String] = []
	var module_lines: Array[String] = []

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

		# 완료 센티넬은 run() 자체가 중단된 경우만 잡는다.
		# 서브테스트(_test_*)에서 에러가 나면 GDScript는 그 함수만 중단하고 run()으로
		# 돌아오므로 t.done()이 정상 호출되고 모듈은 통과처럼 보인다.
		# 그래서 어서션 개수도 함께 검증한다 — 서브테스트가 통째로 건너뛰어지면 수가 모자란다.
		if not t.completed:
			all_failures.append("%s :: 모듈이 끝까지 실행되지 않았다 — run()이 중간에 중단됐다 (stderr 확인)" % path.get_file())
		var expected: int = int(script.get_script_constant_map().get("EXPECTED_CHECKS", -1))
		if expected < 0:
			all_failures.append("%s :: EXPECTED_CHECKS 상수가 없다 — 서브테스트 중단을 감지할 수 없다" % path.get_file())
		elif t.checks != expected:
			all_failures.append("%s :: 어서션 %d개를 기대했는데 %d개가 실행됐다 — 서브테스트가 중단됐거나, 어서션을 바꾸고 EXPECTED_CHECKS를 갱신하지 않았다"
				% [path.get_file(), expected, t.checks])

		module_lines.append("  %-28s %3d checks" % [path.get_file(), t.checks])
		total_checks += t.checks
		for failure: String in t.failures:
			all_failures.append("%s :: %s" % [path.get_file(), failure])

	print("")
	for line: String in module_lines:
		print(line)
	print("checks: %d, failures: %d" % [total_checks, all_failures.size()])
	for failure: String in all_failures:
		print("  FAIL  %s" % failure)
	if all_failures.is_empty():
		print("ALL PASS")
		quit(0)
	else:
		quit(1)
