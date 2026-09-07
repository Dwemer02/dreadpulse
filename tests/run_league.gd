extends SceneTree
## 자동 조립 리그 배치 러너.
##
## 실행:
##   godot --headless --path . --script res://tests/run_league.gd -- --repeats=5
##
## `--repeats=N`은 조건당 반복 시드 수다. 참가자 수 = 전략 5 × 풀 10 × N
## (유연형 4 + 고정 레시피 비교군 1, r5b §7.2).
##   1  → 50명   기능 검수
##   5  → 250명  소규모 탐색 (선택 의도·사망 원인 확인)
##   20 → 1000명 1차 탐색
##
## **이 리그의 승률을 실제 PvE 난이도나 인간 승률로 해석하지 않는다** (기획서 §1.3).

const Config = preload("res://league/league_config.gd")
const LeagueContent = preload("res://league/league_content.gd")
const Runner = preload("res://league/league_runner.gd")
const Reporter = preload("res://league/reporter.gd")
const PartMeta = preload("res://league/part_meta.gd")

func _init() -> void:
	var config: RefCounted = Config.new()
	config.repeats_per_condition = _arg_int("repeats", 5)
	config.batch_id = "r%d" % config.repeats_per_condition

	# 커밋·dirty를 **실행 시작에** 캡처한다. 끝에 읽으면 배치 도중의 커밋이 잡힌다 —
	# r5b의 manifest가 실제로 그렇게 됐다 (r5b 피드백 §10.1).
	config.capture_version()

	var content: RefCounted = LeagueContent.new()
	content.load_all()
	if not content.ok():
		for e: String in content.errors:
			print("  CONTENT  %s" % e)
		quit(1)
		return

	var coverage: Dictionary = PartMeta.coverage_report(content.meta_index)
	var started: int = Time.get_ticks_msec()

	var runner: RefCounted = Runner.new()
	runner.setup(config, content)
	runner.run()

	var elapsed: float = float(Time.get_ticks_msec() - started) / 1000.0
	var reporter: RefCounted = Reporter.new()
	print(reporter.report(runner, coverage))
	print("")
	print("실행 시간 %.1f초 · 매치 %d회 · 선택 %d회 · 스냅샷 %d개"
		% [elapsed, runner.matches.size(), runner.choices.size(), runner.snapshots.size()])
	print("출력: %s (실행마다 새 폴더 — 덮어쓰지 않는다)" % reporter.out_dir)
	quit(0)

func _arg_int(name: String, fallback: int) -> int:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name):
			return int(arg.split("=")[1])
	return fallback
