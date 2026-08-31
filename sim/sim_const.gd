extends RefCounted
## 전투 시뮬레이션의 불변 상수. 여기 있는 값은 밸런스 수치가 아니라 계약이다.
## 스펙 §4를 참조. 의존 없음 — sim/ 전체가 이것을 preload한다.

## 고정 틱. 이벤트의 t 필드를 만들 때만 쓴다. 내부 시간 계산은 전부 정수 틱이다.
const TICK_DT: float = 0.05

## 발동 상한 초당 5회 = 마지막 발동으로부터 4틱(0.2초) 미경과 시 발동 불가. 스펙 §4.2
const MIN_FIRE_TICKS: int = 4

## 체인 깊이 상한. 초과 시 chain_capped 이벤트. 스펙 §4.6
const MAX_CHAIN_DEPTH: int = 12

## 무제한 파츠가 drain_fires를 처음 맞을 때 확정되는 수명. 스펙 §4.5
const DEFAULT_FIRE_LIMIT: int = 5

## 발동 누적 8회마다 공명 +1. 스펙 §7.2
const RESONANCE_PER_FIRES: int = 8

## 전투 시간 상한. 초과 시 잔여 HP 비율로 판정. 스펙 §4.1
const MAX_COMBAT_TICKS: int = 2400  # 120초

## 재생·과열이 적용되는 주기 (1초)
const PERIOD_TICKS: int = 20

# --- 공격 / 방어 타입 (스펙 §21.1) ---

## 배율은 정수 분수로 둔다. 부동소수는 드리프트를 만들고, 그것이 결정론을 깬다 —
## 쿨타임 속도를 SPEED_NORMAL=2로 두는 것과 같은 이유다.
## 분모 4. ×0.75 → 3, ×1.0 → 4, ×1.5 → 6.
const TYPE_MULT_DENOM: int = 4

const ATTACK_TYPES: Array[String] = ["physical", "thermal", "caustic", "energy"]
## 방어 타입 3종. plating/biomass는 선체 재질(Core가 정한다), energy_shield는 그 위의 층.
const DEFENSE_TYPES: Array[String] = ["plating", "biomass", "energy_shield"]
## 선체 재질은 이 둘 중 하나다. energy_shield는 재질이 아니다.
const HULL_MATERIALS: Array[String] = ["plating", "biomass"]

## 타입을 명시하지 않은 피해. 전부 ×1.0이므로 상성이 없다 —
## 타입 체계를 모르는 플레이어의 안전밸브이자, 기존 콘텐츠의 수치를 보존하는 기본값이다.
const DEFAULT_ATTACK_TYPE: String = "physical"

## 공격 타입 -> 방어 타입 -> 배율 분자. 하한은 0이 아니다 (GDD §3.4) —
## 면역과 무효는 이 게임에 존재하지 않는다.
const TYPE_MULT: Dictionary = {
	"physical": {"plating": 4, "biomass": 4, "energy_shield": 4},
	"thermal":  {"plating": 3, "biomass": 6, "energy_shield": 4},
	"caustic":  {"plating": 6, "biomass": 4, "energy_shield": 3},
	"energy":   {"plating": 4, "biomass": 3, "energy_shield": 6},
}

## 선체 재질 기본값. Core가 방어 타입 키워드를 갖지 않으면 이것으로 본다.
const DEFAULT_HULL_MATERIAL: String = "plating"

# --- 상태이상 (스펙 §21.2) ---

## Corrosion 제거: 실제 회복 이만큼당 중첩 1. 풀피에서 수리해도 실제 회복이 0이므로
## 제거되지 않는다. 초기 테스트값이다.
const REPAIR_PER_CORROSION_CLEANSE: int = 10

## 쿨타임 진행 속도 유닛. 정수라서 드리프트가 없다. 스펙 §6.5
const SPEED_NORMAL: int = 2
const SPEED_ACCEL: int = 4   # 가속: 정확히 2배
const SPEED_SLOW: int = 1    # 둔화: 정확히 절반

## 무제한 발동 횟수 / 영구 지속시간 센티넬
const UNLIMITED: int = -1
const PERMANENT: int = -1

static func secs_to_ticks(secs: float) -> int:
	if secs < 0.0:
		return PERMANENT
	return int(round(secs / TICK_DT))

static func ticks_to_secs(ticks: int) -> float:
	return float(ticks) * TICK_DT

## 쿨타임(초)을 진행 유닛 목표치로. 보통 속도로 정확히 그 초가 걸린다.
static func cooldown_to_units(secs: float) -> int:
	return secs_to_ticks(secs) * SPEED_NORMAL
