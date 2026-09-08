extends SceneTree
## 첫 전투용 적을 **별도로 검수한다** (A~G 검토 §6.4 마지막: "첫 전투용 3파츠 적
## 2종은 별도로 검수해 만든다").
##
## 실행:
##   godot --headless --path . --script res://tests/check_starter_enemies.gd
##
## 후보 조합을 고정 상대군 archive-1에 붙여 강도를 비교한다. **archive-1의 승률이
## 사람 난이도는 아니다** — 다만 "이 후보가 G의 초반 후보보다 센가 약한가"는 같은
## 자에서 재야 알 수 있고, 첫 전투 상대가 2~3전투 상대보다 세면 곡선이 뒤집힌다.
##
## 첫 판본이 그렇게 뒤집혔다: 고철 기관포 2정 + 재주조 포신이 74.1%로 나와
## G의 초반 후보 셋(58~73%)보다 셌다.

const LeagueContent = preload("res://league/league_content.gd")
const VoyageConfig = preload("res://voyage/voyage_config.gd")
const Benchmark = preload("res://league/benchmark.gd")
const Archive = preload("res://league/opponent_archive.gd")

## 후보. {이름: [본체 파츠...]} — Core는 자동으로 붙는다.
const VARIANTS: Dictionary = {
	"현재 gun (기관포2+재주조)": ["scrap_autocannon", "scrap_autocannon", "recast_barrel"],
	"기관포1+재주조+침식": ["scrap_autocannon", "recast_barrel", "erosion_extruder"],
	"기관포1+재주조": ["scrap_autocannon", "recast_barrel"],
	"기관포1+침식+회수기": ["scrap_autocannon", "erosion_extruder", "waste_heat_recovery"],
	"산성절단+침식+회수기": ["acid_jet_cutter", "erosion_extruder", "waste_heat_recovery"],
	"현재 ward (산성절단+용접+대출막)": ["acid_jet_cutter", "field_welder", "loan_shield_membrane"],
	"산성절단+용접": ["acid_jet_cutter", "field_welder"],
	"기관포+용접+대출막": ["scrap_autocannon", "field_welder", "loan_shield_membrane"],
}

func _init() -> void:
	var content: RefCounted = LeagueContent.new()
	content.load_all()
	if not content.ok():
		for e: String in content.errors:
			print("  CONTENT  %s" % e)
		quit(1)
		return
	var config: RefCounted = VoyageConfig.make(1).league
	var opponents: Array = Archive.load_all()
	var slots: Array = content.slots_of(config)

	print("")
	print("── 첫 전투 후보 검수 — 고정 상대군 %s"
		% str(Archive.manifest()["version"]))
	print("  %-34s %7s %8s %8s %9s" % ["구성", "승률", "격차", "평균초", "OFF미해결"])
	for name: String in VARIANTS:
		var build: Dictionary = _build(VARIANTS[name], slots, config)
		var on: Dictionary = Benchmark.run(content.catalog, config, build,
			opponents, config.combat_rules(), name, Benchmark.SEEDS, true)
		var off: Dictionary = Benchmark.run(content.catalog, config, build,
			opponents, Benchmark.no_overtime_rules(), name, Benchmark.SEEDS, true)
		var paired: Dictionary = Benchmark.pair(on["per_match"], off["per_match"])
		print("  %-34s %6.1f%% %+8.1f %8.1f %9d"
			% [name, 100.0 * float(on["win_rate"]), float(on["avg_margin"]),
				float(on["avg_elapsed"]), int(paired["a_only"])])
	print("")
	print("  ※ 첫 전투 상대는 G의 초반 후보(58~73%)보다 **낮아야** 곡선이 올라간다.")
	print("  ※ OFF미해결이 크면 '굳는' 상대다 — 사람이 120초를 기다리게 된다.")
	quit(0)

## 역할에 맞는 첫 빈 슬롯에 차례로 놓는다.
func _build(parts: Array, slots: Array, config: RefCounted) -> Dictionary:
	var out: Dictionary = {}
	for slot_def: Dictionary in slots:
		if str(slot_def["role"]) == "core":
			out[str(slot_def["id"])] = {"part": config.core_id}
	var content: RefCounted = LeagueContent.new()
	content.load_all()
	for part_id: Variant in parts:
		var role: String = str((content.catalog.parts
			as Dictionary)[str(part_id)]["base_role"])
		for slot_def2: Dictionary in slots:
			var slot_id: String = str(slot_def2["id"])
			var slot_role: String = str(slot_def2["role"])
			if slot_role == "core" or out.has(slot_id):
				continue
			if slot_role == role or slot_role == "flexible":
				out[slot_id] = {"part": str(part_id)}
				break
	return {"id": "starter_variant", "frame": config.frame_id, "relic": null,
		"slots": out}
