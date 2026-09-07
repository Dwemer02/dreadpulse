extends RefCounted
## 자동 조립 리그의 규칙·조건·시드. 기획서 §16의 YAML을 그대로 옮긴 것이다.
##
## **여기 있는 수치는 전부 리그용 임시 규칙이고 본편 확정 규칙이 아니다** (기획서 §2).
## 초과 피해·손실 상한·보관 한도는 실험 장치이지 게임 규칙이 아니므로, 이 파일 밖으로
## 새어 나가면 안 된다.
##
## 기존 게임에 이미 규칙이 있는 항목은 여기에 **없다** — 그쪽을 그대로 쓴다 (§15).
## 없는 것만 여기 있다: 보관 한도, 초과 피해, 손실·라운드 상한, 팩션 풀.

const Inventory = preload("res://run/inventory.gd")
const Evaluator = preload("res://league/build_evaluator.gd")

## 시드 도출 규칙의 버전. 이 문자열이 바뀌면 같은 반복 시드라도 다른 배치다.
const SEED_RULE := "fnv1a-mix-v1"

# --- 리그 진행 ---
var loss_limit: int = 4
var round_cap: int = 15
var protected_rounds: int = 0
var draw_loss_cost: int = 1

# --- 시작과 보상 ---
var start_random_parts: int = 1
var start_choice_rounds: int = 2
var options_per_choice: int = 3
var require_three_bodies: int = 3
var start_allow_augment: bool = false

## 예비 보관 한도. 기존 코드에는 한도가 없었지만 그것은 결정이 아니라 미구현이었다 —
## 런은 Salvage가 5회뿐이라 한 번도 문제가 되지 않았다. 리그는 최대 17회 획득한다.
## 한도가 없으면 폐기 판단이 사라지고 엔진 투자형이 무한히 쟁여둘 수 있다.
var storage_limit: int = 6

# --- 조립 탐색 ---
var candidate_depth: int = 2
var beam_width: int = 8
var shortlist_size: int = 3
var shortlist_score_gap: float = 1.0
var rank_weights: Array[int] = [60, 30, 10]
var goal_reconsider_after: int = 3

# --- 매칭 ---
var random_opening_rounds: int = 2
var later_random_fraction: float = 0.20

# --- 전투 ---
## 초과 피해. 60초 유예, 61초부터 매초, 120초 최종 종료.
## damage(k) = reference_hull × base_fraction × k
var overtime_start_seconds: float = 60.0
var overtime_base_fraction: float = 0.001
## 기준 선체는 **배치 공통값**이지 참가자의 현재/최대 선체가 아니다 (§9.2).
var overtime_reference_hull: int = 100
var timeout_result: String = "draw"

# --- 함선 골격 ---
## 기존 테스트 함선을 그대로 쓴다 (§15의 "현재 프로젝트에 테스트 함선이 있다면 우선").
## pool_frame = Core + weapon_1 + defense_1 + flex ×3, 선체 100.
## flex가 3칸이라 역할 슬롯 제약이 약한 골격이다 — 역할 제약을 실험 축으로 보고 싶으면
## 별도 Frame이 필요하다. 리포트에 그대로 적는다.
var frame_id: String = "pool_frame"
var core_id: String = "league_core"

# --- 실행 규모 ---
var repeats_per_condition: int = 20

# --- 버전 (재현용 — 리포트 머리에 그대로 찍는다) ---
var game_version: String = "parts-90"
var ai_version: String = "league-ai-1"
var league_version: String = "league-1"
var batch_id: String = "batch"

## 팩션 보상 풀 10종 (§7). 값은 제안 파츠 **하나하나의** 추첨 확률이다 —
## 70:30을 매번 2개:1개로 강제하지 않는다.
const POOLS: Dictionary = {
	"r100":    {"reclaimer": 100, "viridia": 0,   "aeonic": 0},
	"v100":    {"reclaimer": 0,   "viridia": 100, "aeonic": 0},
	"a100":    {"reclaimer": 0,   "viridia": 0,   "aeonic": 100},
	"r70_v30": {"reclaimer": 70,  "viridia": 30,  "aeonic": 0},
	"r70_a30": {"reclaimer": 70,  "viridia": 0,   "aeonic": 30},
	"v70_r30": {"reclaimer": 30,  "viridia": 70,  "aeonic": 0},
	"v70_a30": {"reclaimer": 0,   "viridia": 70,  "aeonic": 30},
	"a70_r30": {"reclaimer": 30,  "viridia": 0,   "aeonic": 70},
	"a70_v30": {"reclaimer": 0,   "viridia": 30,  "aeonic": 70},
	"equal":   {"reclaimer": 34,  "viridia": 33,  "aeonic": 33},
}

const STRATEGIES: Array[String] = ["immediate", "engine", "sustain", "bridge"]

static func pool_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in POOLS:
		out.append(id)
	return out

## 전투 시뮬레이터에 주입할 선택 규칙. combat_sim.rules가 이것을 받는다.
func combat_rules() -> Dictionary:
	return {
		"overtime_start_seconds": overtime_start_seconds,
		"overtime_base_fraction": overtime_base_fraction,
		"overtime_reference_hull": overtime_reference_hull,
		"timeout_result": timeout_result,
	}

## 리포트 머리에 찍는 재현 정보. 여기 없는 값으로 결과가 달라지면 재현이 깨진 것이다.
##
## **결과 파일만 받은 사람이 실험을 점검할 수 있어야 한다** (r5 피드백 §8.2).
## r5 manifest에는 커밋·엔진 버전·실제 가중치·시드 도출 규칙이 없어서, 코드를
## 함께 받지 않으면 무엇을 돌린 것인지 확인할 방법이 없었다.
func manifest() -> Dictionary:
	return {
		"batch_id": batch_id,
		"git_commit": git_commit(),
		"godot_version": Engine.get_version_info()["string"],
		"game_version": game_version,
		"ai_version": ai_version,
		"league_version": league_version,
		"seed_rule": SEED_RULE,
		"strategy_weights": Evaluator.WEIGHTS,
		"normalizers": {
			"output_full": Evaluator.OUTPUT_FULL, "sustain_full": Evaluator.SUSTAIN_FULL,
			"connection_full": Evaluator.CONNECTION_FULL, "dead_full": Evaluator.DEAD_FULL,
			"surplus_full": Evaluator.SURPLUS_FULL, "unlock_full": Evaluator.UNLOCK_FULL,
			"resolved_full": Evaluator.RESOLVED_FULL,
		},
		"pools": POOLS,
		"repeat_seeds": range(1, repeats_per_condition + 1),
		"loss_limit": loss_limit, "round_cap": round_cap,
		"protected_rounds": protected_rounds,
		"storage_limit": storage_limit,
		"candidate_depth": candidate_depth, "beam_width": beam_width,
		"shortlist_size": shortlist_size, "shortlist_score_gap": shortlist_score_gap,
		"frame_id": frame_id, "core_id": core_id,
		"repeats_per_condition": repeats_per_condition,
		"combat": combat_rules(),
	}

# --- 난수 분리 (§10.2) ---
#
# 언어 런타임의 hash()를 쓰지 않는다 — 엔진 버전에 따라 값이 달라져 배치 간 비교가
# 조용히 깨진다. sim의 전투 시드 파생과 같은 규칙(곱셈 + 큰 소수)을 쓴다.

const MASK: int = 0x7fffffff

static func mix(parts: Array) -> int:
	var acc: int = 2166136261
	for value: Variant in parts:
		acc = (acc * 16777619 + _scalar(value)) & MASK
	return acc

## 문자열도 결정론적인 정수로 바꾼다. 짧은 id만 들어오므로 이 정도면 충분하다.
static func _scalar(value: Variant) -> int:
	if value is int:
		return int(value) & MASK
	var text: String = str(value)
	var acc: int = 7
	for i: int in text.length():
		acc = (acc * 131 + text.unicode_at(i)) & MASK
	return acc

## 현재 커밋. `.git`을 직접 읽는다 — 결과 파일만 보고 코드를 되찾을 수 있어야 한다.
## 읽을 수 없으면 빈 문자열이고, 그것도 정보다 (내보낸 빌드에서 돌렸다는 뜻).
static func git_commit() -> String:
	var head: FileAccess = FileAccess.open("res://.git/HEAD", FileAccess.READ)
	if head == null:
		return ""
	var text: String = head.get_as_text().strip_edges()
	if not text.begins_with("ref: "):
		return text
	var ref: FileAccess = FileAccess.open("res://.git/" + text.substr(5), FileAccess.READ)
	if ref == null:
		return ""
	return ref.get_as_text().strip_edges()

static func rng_for(parts: Array) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = mix(parts)
	return rng
