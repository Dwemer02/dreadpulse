extends RefCounted
## 보유 파츠와 슬롯 배치.
##
## 보유 파츠는 **파츠 id의 집합이 아니라 인스턴스 목록**이다. 같은 파츠를 두 번
## Salvage할 수 있고(고철 기관포 2정은 유효한 빌드다), 하나의 인스턴스는 한 슬롯에만
## 들어간다 — Active로 쓰면 그 인스턴스를 Augment로는 못 쓴다.
## 그래서 배치는 part_id가 아니라 uid로 가리킨다.

## 보유 인스턴스: [{ "uid": int, "part_id": String }]
var owned: Array = []
## 배치: slot_id -> { "active": uid, "augment": uid }  (augment는 -1이면 없음)
var board: Dictionary = {}

var _next_uid: int = 1

const NONE: int = -1

# --- 보유 ---

## 파츠 하나를 획득한다. 인스턴스 uid를 돌려준다.
func add(part_id: String) -> int:
	var uid: int = _next_uid
	_next_uid += 1
	owned.append({"uid": uid, "part_id": part_id})
	return uid

func part_id_of(uid: int) -> String:
	for item: Dictionary in owned:
		if int(item["uid"]) == uid:
			return str(item["part_id"])
	return ""

func owned_part_ids() -> Array[String]:
	var out: Array[String] = []
	for item: Dictionary in owned:
		out.append(str(item["part_id"]))
	return out

# --- 배치 ---

## 슬롯에 Active(+Augment)를 놓는다. 다른 슬롯에 이미 있던 인스턴스면 그쪽에서 뗀다 —
## 한 인스턴스는 한 자리에만 있을 수 있다는 규칙을 여기서 지킨다.
func place(slot_id: String, active_uid: int, augment_uid: int = NONE) -> void:
	for uid: int in [active_uid, augment_uid]:
		if uid != NONE:
			_detach(uid)
	board[slot_id] = {"active": active_uid, "augment": augment_uid}

func clear(slot_id: String) -> void:
	board.erase(slot_id)

func slot_of(uid: int) -> String:
	for slot_id: String in board:
		var entry: Dictionary = board[slot_id]
		if int(entry["active"]) == uid or int(entry["augment"]) == uid:
			return slot_id
	return ""

func is_placed(uid: int) -> bool:
	return slot_of(uid) != ""

## 아직 어느 슬롯에도 없는 인스턴스. 창고다.
func unplaced() -> Array:
	var out: Array = []
	for item: Dictionary in owned:
		if not is_placed(int(item["uid"])):
			out.append(item)
	return out

## uid를 지금 있는 자리에서 떼낸다. Active를 떼면 그 슬롯의 Augment도 함께 풀린다 —
## 숙주 없는 Augment는 존재할 수 없다.
func _detach(uid: int) -> void:
	var slot_id: String = slot_of(uid)
	if slot_id == "":
		return
	var entry: Dictionary = board[slot_id]
	if int(entry["active"]) == uid:
		board.erase(slot_id)
	else:
		entry["augment"] = NONE

# --- 빌드 생성 ---

## build_loader가 먹는 형태로 만든다. 빈 슬롯은 넣지 않는다 — assemble()이
## 이미 허용한다(Core만 필수). 스타터가 4파츠인데 프레임이 6슬롯인 것은 의도된 것이다.
func to_build(build_id: String, frame_id: String) -> Dictionary:
	var slots: Dictionary = {}
	for slot_id: String in board:
		var entry: Dictionary = board[slot_id]
		var active_id: String = part_id_of(int(entry["active"]))
		if active_id == "":
			continue
		var out: Dictionary = {"part": active_id}
		var augment_id: String = part_id_of(int(entry.get("augment", NONE)))
		if augment_id != "":
			out["augment"] = augment_id
		slots[slot_id] = out
	return {"id": build_id, "frame": frame_id, "relic": null, "slots": slots}

# --- Tune 계측 ---

## 비교용 배치 스냅샷. Tune 전에 찍어두고 후와 비교한다.
func snapshot() -> Dictionary:
	return board.duplicate(true)

## 두 스냅샷의 차이. §10의 "전투 직전 교체한 Active 수 / 변경한 Augment 수"가 이 값이다.
##
## `moved`는 같은 인스턴스가 다른 슬롯으로 옮겨간 수다. Active 교체와 겹쳐 세어지므로
## 합산하지 말고 참고값으로 읽는다 — 슬롯 재배치와 파츠 교체는 다른 행동이다.
static func board_diff(before: Dictionary, after: Dictionary) -> Dictionary:
	var slots: Dictionary = {}
	for slot_id: String in before:
		slots[slot_id] = true
	for slot_id: String in after:
		slots[slot_id] = true

	var active_changed: int = 0
	var augment_changed: int = 0
	for slot_id: String in slots:
		var b: Dictionary = before.get(slot_id, {})
		var a: Dictionary = after.get(slot_id, {})
		if int(b.get("active", NONE)) != int(a.get("active", NONE)):
			active_changed += 1
		if int(b.get("augment", NONE)) != int(a.get("augment", NONE)):
			augment_changed += 1

	var moved: int = 0
	for uid: int in _placed_uids(before):
		var was: String = _slot_in(before, uid)
		var now: String = _slot_in(after, uid)
		if now != "" and now != was:
			moved += 1
	return {"active": active_changed, "augment": augment_changed, "moved": moved}

static func _placed_uids(snap: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for slot_id: String in snap:
		var entry: Dictionary = snap[slot_id]
		for key: String in ["active", "augment"]:
			var uid: int = int(entry.get(key, NONE))
			if uid != NONE and not out.has(uid):
				out.append(uid)
	return out

static func _slot_in(snap: Dictionary, uid: int) -> String:
	for slot_id: String in snap:
		var entry: Dictionary = snap[slot_id]
		if int(entry.get("active", NONE)) == uid or int(entry.get("augment", NONE)) == uid:
			return slot_id
	return ""
