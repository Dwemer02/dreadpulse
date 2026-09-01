extends RefCounted
## Phase 0 콘텐츠 레지스트리 — 무엇이 "실제 콘텐츠"인지 한 곳에 적는다.
##
## tests/(배치 러너)와 debug/(시각화)가 같은 카탈로그·같은 빌드 목록을 쓰게 만드는 것이
## 존재 이유다. 디렉터리를 훑지 않고 명시적 목록을 쓴다 — 나열 순서가 곧 배치 실행 순서
## (결정론 계약)이고, 내보낸 빌드에서 res:// 디렉터리 나열은 신뢰할 수 없기 때문이다.
##
## 테스트용 파츠 풀 21종(팩션당 7종)이 들어 있다. 수치와 구성은 전부 잠정이다.

const Catalog = preload("res://sim/catalog.gd")
const BuildLoader = preload("res://sim/build_loader.gd")
const CombatSim = preload("res://sim/combat_sim.gd")

## standard_frame은 옛 픽스처(Core 슬롯 있음)가 계속 쓴다.
## pool_frame은 테스트 풀 전용이다 — 이 풀에는 Core 파츠가 없어서 Core 슬롯도 없다.
const FRAME_PATHS: Array[String] = [
	"res://sim/data/frames/standard_frame.json",
	"res://sim/data/frames/pool_frame.json",
]
const PART_PATHS: Array[String] = [
	"res://sim/data/parts/reclaimer.json",
	"res://sim/data/parts/viridia.json",
	"res://sim/data/parts/aeonic.json",
]
const RELIC_PATHS: Array[String] = ["res://sim/data/relics/relics.json"]

## 구현된 팩션. 배치 리포트가 "측정 불가"를 정직하게 표시하는 데 쓴다.
const IMPLEMENTED_FACTIONS: Array[String] = ["reclaimer", "viridia", "aeonic"]

## 플레이어 빌드 id -> 경로. 팩션당 순수 빌드 하나씩.
const BUILD_PATHS: Dictionary = {
	"reclaimer_pure": "res://sim/data/builds/reclaimer_pure.json",
	"viridia_pure": "res://sim/data/builds/viridia_pure.json",
	"aeonic_pure": "res://sim/data/builds/aeonic_pure.json",
}

## 적 빌드 id -> 경로. 적은 플레이어와 같은 ShipState에 고정 빌드를 얹은 것뿐이다.
## 지금은 순수 빌드의 거울짝이다 — 파츠 자체를 보려는 것이지 적 설계를 보려는 것이 아니다.
const ENEMY_PATHS: Dictionary = {
	"reclaimer_mirror": "res://sim/data/enemies/reclaimer_mirror.json",
	"viridia_mirror": "res://sim/data/enemies/viridia_mirror.json",
	"aeonic_mirror": "res://sim/data/enemies/aeonic_mirror.json",
}

static func load_catalog() -> RefCounted:
	var c: RefCounted = Catalog.new()
	for path: String in FRAME_PATHS:
		c.load_frame(path)
	for path: String in PART_PATHS:
		c.load_parts(path)
	for path: String in RELIC_PATHS:
		c.load_relics(path)
	return c

static func build_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in BUILD_PATHS:
		out.append(id)
	return out

static func enemy_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in ENEMY_PATHS:
		out.append(id)
	return out

## 빌드 id의 JSON 경로. 없으면 빈 문자열.
static func path_for(id: String) -> String:
	if BUILD_PATHS.has(id):
		return str(BUILD_PATHS[id])
	if ENEMY_PATHS.has(id):
		return str(ENEMY_PATHS[id])
	return ""

## 빌드 JSON 원본을 읽는다 (debug/가 슬롯 배치를 그리는 데 쓴다). 실패하면 빈 Dictionary.
static func read_build(id: String) -> Dictionary:
	var path: String = path_for(id)
	if path == "":
		return {}
	return BuildLoader.new().load_build(path)

## 전투 하나를 조립한다. 실패하면 {"sim": null, "errors": [...]}.
## 카탈로그는 호출자가 한 번만 로드해서 넘긴다 — 배치는 수천 판을 돌린다.
static func prepare(catalog: RefCounted, player_id: String, enemy_id: String,
		combat_seed: int) -> Dictionary:
	var player_path: String = path_for(player_id)
	if player_path == "":
		return {"sim": null, "errors": ["알 수 없는 빌드 id: %s" % player_id]}
	var enemy_path: String = path_for(enemy_id)
	if enemy_path == "":
		return {"sim": null, "errors": ["알 수 없는 빌드 id: %s" % enemy_id]}

	var loader: RefCounted = BuildLoader.new()
	var player: RefCounted = loader.assemble(loader.load_build(player_path), catalog, "player")
	var enemy: RefCounted = loader.assemble(loader.load_build(enemy_path), catalog, "enemy")
	if player == null or enemy == null:
		return {"sim": null, "errors": loader.errors}

	var sim: RefCounted = CombatSim.new()
	sim.setup(player, enemy, combat_seed)
	return {"sim": sim, "errors": []}
