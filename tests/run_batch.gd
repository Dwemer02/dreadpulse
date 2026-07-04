extends SceneTree
# 배치 검증 러너: 승률표 + GDD §10 검증 지표 3종.
# 실행: & $godot --headless --path . --script res://tests/run_batch.gd

const Sim := preload("res://sim/combat_sim.gd")
const Loader := preload("res://sim/build_loader.gd")

const SEEDS := 50
const OUT_DIR := "res://tests/out"

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var builds := {}
	for n in ["pure_steel", "overdrive", "bloodpressure", "gaze", "dummy_tank"]:
		builds[n] = Loader.load_build("res://sim/builds/%s.json" % n)
	_win_matrix(builds)
	_metric1_pulse_curve(builds)
	_metric2_tentacle_overtake(builds)
	_metric3_misfire(builds)
	quit(0)

func _run(a: Dictionary, b: Dictionary, seed_value: int,
		on_events: Callable = Callable()) -> Dictionary:
	var sim = Sim.new()
	sim.setup(a, b, seed_value)
	return sim.run_to_end(on_events)

func _win_matrix(builds: Dictionary) -> void:
	var names := ["pure_steel", "overdrive", "bloodpressure", "gaze"]
	print("\n=== 승률표 (%d시드, 값 = 행 빌드의 승률, 무승부 제외) ===" % SEEDS)
	for an in names:
		var row := "%-14s| " % an
		for bn in names:
			if an == bn:
				row += "   --    "
				continue
			var wins := 0
			for s in SEEDS:
				var r := _run(builds[an], builds[bn], 1000 + s)
				if int(r.winner) == 0:
					wins += 1
			var rate := 100.0 * wins / SEEDS
			row += "%s:%3.0f%% " % [bn.substr(0, 4), rate]
			if rate >= 90.0:
				row += "(!) "
		print(row)
	print("(!) = 90%% 이상 일방 승리 — 밸런스 경고")

func _metric1_pulse_curve(builds: Dictionary) -> void:
	print("\n=== 지표1: 폭주(overdrive) 펄스 지수 곡선 (vs dummy_tank, seed 42) ===")
	var windows: Array = []  # 10초 창별 side0 pulse_emitted 수
	var collector := func(evs: Array) -> void:
		for e in evs:
			if e.type == "pulse_emitted" and int(e.side) == 0:
				var w := int((int(e.tick) * Sim.TICK_DT) / 10.0)
				while windows.size() <= w:
					windows.append(0)
				windows[w] = int(windows[w]) + 1
	var r := _run(builds["overdrive"], builds["dummy_tank"], 42, collector)
	var f := FileAccess.open(OUT_DIR + "/metric1_pulse_curve.csv", FileAccess.WRITE)
	f.store_line("window_10s,pulses")
	for i in windows.size():
		f.store_line("%d,%d" % [i, windows[i]])
	f.close()
	print("  전투 시간 %.1fs (%s), 창별 펄스: %s" % [r.time, r.reason, windows])
	var first := int(windows[0]) if windows.size() > 0 else 0
	var peak := 0
	for w in windows:
		peak = maxi(peak, int(w))
	var ratio := float(peak) / maxf(float(first), 1.0)
	var ok := first > 0 and ratio >= 1.5
	print("  peak/first = %.2f (기준 >= 1.5) → %s" % [ratio, "합격" if ok else "불합격"])

func _metric2_tentacle_overtake(builds: Dictionary) -> void:
	print("\n=== 지표2: 촉수 누적피해의 주포 추월 (bloodpressure vs dummy_tank, seed 42) ===")
	var state := {"tentacle": 0, "turret": 0, "cross": -1.0}
	var collector := func(evs: Array) -> void:
		for e in evs:
			if e.type == "damage_dealt" and int(e.side) == 0 and not e.get("absorbed", false):
				if str(e.source_type) == "tentacle":
					state.tentacle = int(state.tentacle) + int(e.amount)
				elif str(e.source_type) == "main_turret":
					state.turret = int(state.turret) + int(e.amount)
				if float(state.cross) < 0.0 and int(state.turret) > 0 \
						and int(state.tentacle) > int(state.turret):
					state.cross = int(e.tick) * Sim.TICK_DT
	var r := _run(builds["bloodpressure"], builds["dummy_tank"], 42, collector)
	print("  전투 %.1fs, 촉수 누적 %d vs 주포 누적 %d, 추월 시점 %.1fs"
		% [r.time, state.tentacle, state.turret, state.cross])
	var ok: bool = float(state.cross) >= 0.0 and float(state.cross) <= 60.0
	print("  기준: 60초 내 추월 → %s" % ("합격" if ok else "불합격"))

func _metric3_misfire(builds: Dictionary) -> void:
	print("\n=== 지표3: 자원 고갈 불발률 (pure_steel vs 보일러 -1 변형, 10시드) ===")
	var rates: Array = []
	for starved in [false, true]:
		var build: Dictionary = (builds["pure_steel"] as Dictionary).duplicate(true)
		if starved:
			build["name"] = "steel_starved"
			build["parts"] = (build["parts"] as Array).filter(
				func(p): return str(p.id) != "b2")
			build["wires"] = (build["wires"] as Array).filter(
				func(w): return not (w as Array).has("b2"))
		var state := {"fired": 0, "missed": 0}
		var collector := func(evs: Array) -> void:
			for e in evs:
				if int(e.get("side", -1)) == 0 and str(e.get("part_type", "")) == "main_turret":
					if e.type == "part_fired":
						state.fired = int(state.fired) + 1
					elif e.type == "misfire":
						state.missed = int(state.missed) + 1
		for s in 10:
			_run(build, builds["pure_steel"], 2000 + s, collector)
		var total: int = int(state.fired) + int(state.missed)
		var rate := 100.0 * int(state.missed) / maxi(total, 1)
		rates.append(rate)
		print("  %-14s: 발사 %d / 불발 %d → 불발률 %.1f%%"
			% [build["name"], state.fired, state.missed, rate])
	var ok: bool = float(rates[1]) > 15.0
	print("  기준: 변형 빌드 불발률 > 15%% → %s" % ("합격" if ok else "불합격"))
