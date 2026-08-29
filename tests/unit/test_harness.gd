extends RefCounted

## 이 모듈이 실행해야 할 어서션 수. 러너가 대조해 서브테스트 중단을 잡는다 —
## _test_* 안에서 에러가 나면 그 함수만 중단되고 run()은 정상 종료하기 때문이다.
const EXPECTED_CHECKS := 4

func run(t: RefCounted) -> void:
	t.eq(1 + 1, 2, "sanity: 덧셈")
	t.check(true, "sanity: check")
	t.eq("intentional", "intentional", "러너가 통과 시 exit 0")
	t.near(1.0, 1.00001, "sanity: near — 기본 허용오차 안")
	t.done()
