extends RefCounted
## 고정 레시피 — "이전에 성공한 조합을 그대로 다시 모으는" 비교군의 목표다 (r5b §7.2·§7.3).
##
## **여기 있는 레시피는 확정이 아니다.** r5b 배치(run_id `r5-20260907T111238`)의
## 상한 생존자 5명의 최종 보드에서 그대로 읽은 것이고, 고정 상대군에서 강도를
## 확인하기 전까지는 "도달 가능한 목표"라는 뜻 이상이 아니다 — r5b 문서 §7.3이
## "효과 원본이 없어 정확한 엔진을 확정하지 않는다"고 명시했다. 단계 D에서 확정한다.
##
## 레시피를 두 층으로 저장한다 (§7.3). 전체 보드가 한 글자도 다르지 않아야 성공이라고
## 정의하면 반복 위험을 **과소평가**한다 — 2~4개 핵심 구성만으로 같은 엔진이 돌기 때문이다.
##   core_engine  필수 파츠 · 개수(multiplicity) · 본체/증강 역할 · 필요한 숙주 관계
##   full_build   발견 당시의 전체 구성 (주변 보조 파츠까지)
##
## 핵심 엔진은 같은 풀·시드에서 상한 생존한 **두 참가자의 교집합**으로 잡았다.
## 한 명만 생존한 조건(equal·시드4)은 교집합을 만들 수 없으므로 그 한 명의 보드에서
## 반복 적재된 부분만 취했다. 어느 쪽이 어느 근거인지 `evidence`에 적는다.

const Inventory = preload("res://run/inventory.gd")

## `core_engine` 각 항목: {part, count, role, host?}
##   role  "body" | "augment"
##   host  증강일 때 필요한 숙주 파츠 id. **증강이 핵심이면 본체로 소유한 것만으로
##         완성 판정하지 않는다** (§7.3) — 숙주 관계까지 맞아야 센다.
const RECIPES: Dictionary = {
	"r100_autocannon_trio": {
		"note": "고철 기관포를 본체로 3개 적재.",
		"evidence": "r5b r100·시드4에서 상한 생존한 참가자 3(즉시형)·103(안정형)의 "
			+ "최종 본체 교집합. 두 참가자 모두 scrap_autocannon 본체 3개였고 "
			+ "나머지 본체는 서로 달랐다 (3은 acid_jet_cutter·neutralizing_washer, "
			+ "103은 field_welder 2개).",
		"core_engine": [
			{"part": "scrap_autocannon", "count": 3, "role": "body"},
		],
		"full_build": {
			"participant": 3,
			"board": [
				["acid_jet_cutter", "field_welder"],
				["neutralizing_washer", "rotary_incinerator"],
				["scrap_autocannon", "field_welder"],
				["scrap_autocannon", "field_welder"],
				["scrap_autocannon", "recast_barrel"],
			],
		},
	},
	"a70_r30_photon_engine": {
		"note": "광자 계열 본체 4종 + 숙주 관계가 고정된 증강 2종.",
		"evidence": "r5b a70_r30·시드3에서 상한 생존한 참가자 87(엔진형)·187(교차형)의 "
			+ "최종 보드 교집합. 본체 4종(helios_lance·photon_lance·"
			+ "returning_photon_shell·scrap_autocannon)이 같고, 증강 2개는 숙주까지 "
			+ "같았다 — photon_lance+fracture_engraver, "
			+ "returning_photon_shell+depletion_recovery_plate.",
		"core_engine": [
			{"part": "helios_lance", "count": 1, "role": "body"},
			{"part": "photon_lance", "count": 1, "role": "body"},
			{"part": "returning_photon_shell", "count": 1, "role": "body"},
			{"part": "scrap_autocannon", "count": 1, "role": "body"},
			{"part": "fracture_engraver", "count": 1, "role": "augment",
				"host": "photon_lance"},
			{"part": "depletion_recovery_plate", "count": 1, "role": "augment",
				"host": "returning_photon_shell"},
		],
		"full_build": {
			"participant": 87,
			"board": [
				["helios_lance", "ephemeral_stellar_tube"],
				["loan_shield_membrane", "eclipse_shield_plate"],
				["photon_lance", "fracture_engraver"],
				["returning_photon_shell", "depletion_recovery_plate"],
				["scrap_autocannon", "ephemeral_stellar_tube"],
			],
		},
	},
	"equal_helios_pair": {
		"note": "헬리오스 창을 본체로 2개 적재.",
		"evidence": "r5b equal·시드4에서 상한 생존한 참가자 148(안정형) 한 명. "
			+ "교집합을 만들 상대가 없으므로 **반복 적재된 부분만** 취했다 — "
			+ "helios_lance 본체 2개. 나머지 본체(dielectric_accumulator·"
			+ "phase_barrier·regen_sac)는 근거가 한 명뿐이라 핵심에 넣지 않았다.",
		"core_engine": [
			{"part": "helios_lance", "count": 2, "role": "body"},
		],
		"full_build": {
			"participant": 148,
			"board": [
				["dielectric_accumulator", "acid_proof_membrane"],
				["helios_lance", "layered_regen_membrane"],
				["helios_lance", "loan_shield_membrane"],
				["phase_barrier", "acid_digest_organ"],
				["regen_sac", "ephemeral_stellar_tube"],
			],
		},
	},
}

## 풀 -> 목표 레시피. **첫 무작위 시작 파츠를 받기 전에 확정한다** (§7.2 계획 시점).
## 시험 런의 시작 파츠를 보고 목표를 바꾸지 않으므로, 여기서 표로 고정해 둔다.
##
## 배정 규칙 (§7.3 "풀별로 강한 기존 레시피를 선택"):
##   1) 그 풀에서 실제로 관측된 레시피가 있으면 그것
##   2) 없으면 핵심 파츠를 전부 구할 수 있는 레시피 중 하나
##   3) 어느 것도 구할 수 없으면 빈 문자열 — **주 비교에서 제외한다**
##
## v100은 3번이다. 세 레시피의 핵심 파츠에 Viridia가 하나도 없다 (관측된 상한
## 생존자 중 Viridia 주력이 없었기 때문이다). **구할 수 없는 풀에서 실패한 횟수로
## "고정 전략은 약하다"고 주장하지 않는다** (§7.3) — 그래서 0으로 채우지 않고 비운다.
const POOL_RECIPE: Dictionary = {
	"r100":    "r100_autocannon_trio",     # 관측
	"v100":    "",                          # 도달 불가 — 제외
	"a100":    "equal_helios_pair",
	"r70_v30": "r100_autocannon_trio",
	"r70_a30": "r100_autocannon_trio",
	"v70_r30": "r100_autocannon_trio",
	"v70_a30": "equal_helios_pair",
	"a70_r30": "a70_r30_photon_engine",    # 관측
	"a70_v30": "equal_helios_pair",
	"equal":   "equal_helios_pair",        # 관측
}

## 이 풀의 목표 레시피 id. 없으면 빈 문자열.
static func recipe_id_for(pool_id: String) -> String:
	return str(POOL_RECIPE.get(pool_id, ""))

static func of(recipe_id: String) -> Dictionary:
	return RECIPES.get(recipe_id, {})

## 이 레시피의 핵심 파츠를 이 풀에서 전부 구할 수 있는가.
##
## 풀 가중치를 인자로 받는다 — league_config가 이 파일을 preload하므로
## 이쪽에서 되짚어 preload하면 순환이 된다.
static func reachable_in(recipe_id: String, weights: Dictionary,
		catalog: RefCounted) -> bool:
	var recipe: Dictionary = of(recipe_id)
	if recipe.is_empty():
		return false
	for entry: Variant in recipe["core_engine"]:
		var part_id: String = str((entry as Dictionary)["part"])
		if not catalog.parts.has(part_id):
			return false
		if int(weights.get(str(catalog.parts[part_id]["faction"]), 0)) <= 0:
			return false
	return true

## 핵심 엔진의 진행도 0.0~1.0.
##
## 보드에 놓인 것만 온전히 센다. 창고에 있는 목표 파츠는 **부분 점수**만 준다 —
## 0이면 "목표 파츠를 합법적으로 보관 가능"(§7.2)이 사문화되고, 1이면 쟁여두는 것이
## 장착과 같은 값이 되어 영원히 창고에 쌓는다.
const STORED_CREDIT: float = 0.4

## 반환: {progress, have, need, stored, missing, complete}
##   have    보드에서 역할·숙주까지 맞은 개수
##   stored  창고에 있는 목표 파츠 개수 (부족분 한도 안에서만)
static func progress(recipe_id: String, inv: RefCounted) -> Dictionary:
	var recipe: Dictionary = of(recipe_id)
	if recipe.is_empty():
		return {"progress": 0.0, "have": 0, "need": 0, "stored": 0,
			"missing": [] as Array[String], "complete": false}
	var stored_counts: Dictionary = {}
	for item: Dictionary in inv.unplaced():
		var sid: String = str(item["part_id"])
		stored_counts[sid] = int(stored_counts.get(sid, 0)) + 1

	var have: int = 0
	var need: int = 0
	var stored: int = 0
	var missing: Array[String] = []
	for entry: Variant in recipe["core_engine"]:
		var spec: Dictionary = entry
		var want: int = int(spec["count"])
		need += want
		var placed: int = _count_placed(inv, spec)
		have += mini(placed, want)
		var short: int = maxi(0, want - placed)
		var reserved: int = mini(short, int(stored_counts.get(str(spec["part"]), 0)))
		stored += reserved
		if short > 0:
			missing.append("%s×%d(%s%s)" % [spec["part"], short, spec["role"],
				"@" + str(spec["host"]) if spec.has("host") else ""])
	if need == 0:
		return {"progress": 0.0, "have": 0, "need": 0, "stored": 0,
			"missing": missing, "complete": false}
	var score: float = (float(have) + STORED_CREDIT * float(stored)) / float(need)
	return {
		"progress": clampf(score, 0.0, 1.0),
		"have": have, "need": need, "stored": stored,
		"missing": missing, "complete": have >= need,
	}

## 보드에서 이 항목을 만족하는 개수. 역할과 (증강이면) 숙주까지 본다.
static func _count_placed(inv: RefCounted, spec: Dictionary) -> int:
	var part_id: String = str(spec["part"])
	var want_augment: bool = str(spec["role"]) == "augment"
	var host: String = str(spec.get("host", ""))
	var count: int = 0
	for slot_id: String in inv.board:
		var entry: Dictionary = inv.board[slot_id]
		var body: String = inv.part_id_of(int(entry.get("active", Inventory.NONE)))
		var augment: String = inv.part_id_of(int(entry.get("augment", Inventory.NONE)))
		if want_augment:
			if augment == part_id and (host == "" or body == host):
				count += 1
		elif body == part_id:
			count += 1
	return count

## 이 레시피가 이 파츠를 원하는가 (역할 무관). 임시 선택과 목표 선택을 로그에서
## 구별하는 데 쓴다.
static func wants(recipe_id: String, part_id: String) -> bool:
	for entry: Variant in of(recipe_id).get("core_engine", []):
		if str((entry as Dictionary)["part"]) == part_id:
			return true
	return false

## manifest에 그대로 찍는다. 결과 파일만 받은 사람이 "무엇을 목표로 삼았는가"를
## 알 수 있어야 한다.
static func manifest() -> Dictionary:
	return {"recipes": RECIPES, "pool_recipe": POOL_RECIPE,
		"stored_credit": STORED_CREDIT}
