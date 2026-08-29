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
