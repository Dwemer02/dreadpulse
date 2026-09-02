extends RefCounted
## 런 1회의 상태 — 팩션 · 인벤토리 · 런 RNG.
##
## 전투 1판의 상태는 `sim/ship_state.gd`다. 이것은 그 위 계층이며 전투를 넘어 남는다.
## 런 계층은 sim에 **데이터를 주입하는 방향**으로만 관여한다 (설계 문서 §3).

const Inventory = preload("res://run/inventory.gd")

var run_seed: int = 0
var faction: String = ""
var frame_id: String = "pool_frame"
var inventory: RefCounted
## Salvage 후보 생성과 적 후보 선정에만 쓴다. 전투 RNG와 섞이면 결정론이 깨진다.
var rng: RandomNumberGenerator

func begin(starter: Dictionary, seed_value: int) -> void:
	run_seed = seed_value
	faction = str(starter.get("faction", ""))
	frame_id = str(starter.get("frame", "pool_frame"))
	rng = RandomNumberGenerator.new()
	rng.seed = seed_value

	inventory = Inventory.new()
	# 스타터의 슬롯을 그대로 인스턴스로 만들어 배치한다.
	# 슬롯 순회 순서가 uid 순서를 정하므로 JSON 키 순서가 결정론에 들어간다.
	var slots: Dictionary = starter.get("slots", {})
	for slot_id: String in slots:
		var entry: Dictionary = slots[slot_id]
		var active_uid: int = inventory.add(str(entry["part"]))
		var augment_uid: int = Inventory.NONE
		if str(entry.get("augment", "")) != "":
			augment_uid = inventory.add(str(entry["augment"]))
		inventory.place(slot_id, active_uid, augment_uid)

## 노드별 전투 시드. 런 시드에서 **결정론적으로 파생**시켜 같은 런 시드로 전체 런이
## 재현되게 한다. `hash()`를 쓰지 않는 이유는 엔진 버전에 따라 값이 달라질 수 있어서다 —
## 리포트 간 비교가 가능해야 하므로 산술 혼합으로 고정한다.
func combat_seed(node_index: int) -> int:
	return (run_seed * 1000003 + node_index * 7919 + 101) & 0x7fffffff

## 이번 전투에 쓸 플레이어 빌드. 매 전투 인벤토리에서 새로 만든다.
func player_build() -> Dictionary:
	return inventory.to_build("run_player", frame_id)
