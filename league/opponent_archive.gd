extends RefCounted
## 고정 상대군 파일을 읽는다 (r5b 피드백 §8.4).
##
## 파일은 `tests/build_opponent_archive.gd`가 r5b 스냅샷에서 한 번 뽑아 얼린 것이고,
## **실행할 때마다 다시 뽑지 않는다.** 다시 뽑으면 배치 간 비교의 기준선이 조용히
## 움직여서 "고정 상대군"이라는 말이 거짓이 된다.

const PATH := "res://league/data/opponent_archive.json"

static func load_archive() -> Dictionary:
	var file: FileAccess = FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		push_error("고정 상대군 파일이 없다: %s — tests/build_opponent_archive.gd로 만든다"
			% PATH)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}

static func load_all() -> Array:
	return (load_archive().get("opponents", []) as Array)

## 특정 구간만. "early" / "mid" / "late".
static func of_stage(stage: String) -> Array:
	var out: Array = []
	for o: Variant in load_all():
		if str((o as Dictionary)["stage"]) == stage:
			out.append(o)
	return out

## manifest에 그대로 찍을 요약. **어떤 상대군에 붙인 결과인지**가 파일에 없으면
## 그 승률은 재현할 수 없는 숫자다.
static func manifest() -> Dictionary:
	var archive: Dictionary = load_archive()
	if archive.is_empty():
		return {"version": "", "opponents": 0}
	var ids: Array[String] = []
	for o: Variant in (archive["opponents"] as Array):
		ids.append(str((o as Dictionary)["id"]))
	return {
		"version": str(archive.get("version", "")),
		"built_from": str(archive.get("built_from", "")),
		"built_commit": str(archive.get("built_commit", "")),
		"selection_rule": archive.get("selection_rule", {}),
		"opponents": ids.size(),
		"opponent_ids": ids,
	}
