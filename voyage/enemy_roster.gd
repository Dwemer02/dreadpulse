extends RefCounted
## 시험 항해의 적 명부. `voyage/data/enemies.json`을 읽는다.
##
## **이 명부는 난이도 확정안이 아니다** (A~G 검토 §6.4). 단계 G의 후보는 "수동 검수를
## 시작할 순서"이고, 원본 라운드는 획득 예산을 짐작하는 단서이지 배치할 스테이지
## 번호가 아니다. 그래서 경로는 데이터로 두고 사람이 고쳐 가며 쓴다.
##
## 손으로 짠 3본체 적 둘은 `source: "authored"`이고, 나머지는 프리셋 보드를 새 id로
## 가져온 것이라 `source`에 원본 프리셋 id가 남아 있다.

const DATA_PATH := "res://voyage/data/enemies.json"

var version: String = ""
## id -> 명부 항목
var by_id: Dictionary = {}
## 경로 id -> [적 id ...]
var paths: Dictionary = {}
var errors: Array[String] = []

func load_all() -> void:
	var text: String = FileAccess.get_file_as_string(DATA_PATH)
	if text.is_empty():
		errors.append("적 명부를 읽을 수 없다: %s" % DATA_PATH)
		return
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		errors.append("적 명부가 Dictionary가 아니다: %s" % DATA_PATH)
		return
	var doc: Dictionary = parsed
	version = str(doc.get("version", ""))
	paths = doc.get("paths", {})
	for row: Variant in doc.get("opponents", []):
		var entry: Dictionary = row
		by_id[str(entry["id"])] = entry
	for path_id: String in paths:
		for enemy_id: Variant in (paths[path_id] as Array):
			if not by_id.has(str(enemy_id)):
				errors.append("경로 %s가 없는 적을 가리킨다: %s"
					% [path_id, str(enemy_id)])

func ok() -> bool:
	return errors.is_empty() and not by_id.is_empty()

## 경로 하나. 없으면 빈 배열 — 호출자가 오류로 다룬다.
func path(path_id: String) -> Array:
	return paths.get(path_id, [])

func entry(enemy_id: String) -> Dictionary:
	return by_id.get(enemy_id, {})

func build_of(enemy_id: String) -> Dictionary:
	return (by_id.get(enemy_id, {}) as Dictionary).get("build", {})

## 용도별 목록. 실험실 화면이 "무엇을 불러올 수 있는가"를 채울 때 쓴다.
func with_role(role: String) -> Array[String]:
	var out: Array[String] = []
	for enemy_id: String in by_id:
		if str((by_id[enemy_id] as Dictionary).get("role", "")) == role:
			out.append(enemy_id)
	out.sort()
	return out

func all_ids() -> Array[String]:
	var out: Array[String] = []
	for enemy_id: String in by_id:
		out.append(enemy_id)
	out.sort()
	return out
