extends RefCounted
## 리그가 쓰는 콘텐츠 로더. sim/content.gd의 표준 카탈로그에 **리그 전용 Core만**
## 덧붙인다.
##
## 리그 Core를 sim/content.gd의 PART_PATHS에 넣지 않는 이유:
##   · 본편 카탈로그의 파츠 수·팩션 분포가 오염된다
##   · Salvage 후보 풀로 새어 들어간다 (런에서 「리그 표준 노심」이 나오면 안 된다)
##   · 리그 규칙이 게임 데이터로 승격된 것처럼 보인다

const Content = preload("res://sim/content.gd")
const PartMeta = preload("res://league/part_meta.gd")

const LEAGUE_PARTS: Array[String] = ["res://league/data/league_core.json"]

var catalog: RefCounted
var meta_index: Dictionary = {}
var errors: Array[String] = []

func load_all() -> void:
	catalog = Content.load_catalog()
	for path: String in LEAGUE_PARTS:
		catalog.load_parts(path)
	errors = catalog.errors.duplicate()
	# 메타데이터는 배치 시작에 **한 번만** 만든다. 800명 × 15라운드 × 수백 후보가
	# 매번 파츠 정의를 다시 훑으면 그 자체가 병목이 된다.
	meta_index = PartMeta.build_index(catalog)

func ok() -> bool:
	return errors.is_empty()

## 리그 참가자의 시작 보드 — Core 하나만 꽂힌 빈 함선.
## 고정 시작 파츠는 없다 (§4.1). Core·Hull·역할 슬롯만 비교 조건으로 고정된다.
func fresh_board(config: RefCounted, inventory: RefCounted) -> void:
	var core_slot: String = ""
	for slot_def: Dictionary in slots_of(config):
		if str(slot_def["role"]) == "core":
			core_slot = str(slot_def["id"])
			break
	if core_slot == "":
		errors.append("Frame %s에 Core 슬롯이 없다" % config.frame_id)
		return
	inventory.place(core_slot, inventory.add(config.core_id))

func slots_of(config: RefCounted) -> Array:
	return (catalog.frames[config.frame_id] as Dictionary)["slots"]

## 참가자가 자유롭게 쓸 수 있는 본체 슬롯 수 (Core 제외).
func body_slot_count(config: RefCounted) -> int:
	var count: int = 0
	for slot_def: Dictionary in slots_of(config):
		if str(slot_def["role"]) != "core":
			count += 1
	return count
