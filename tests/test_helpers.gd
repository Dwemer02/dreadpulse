extends RefCounted
## 테스트 모듈이 결과를 모으는 수집기. 예외를 던지지 않고 실패를 누적한다 —
## GDScript에는 예외가 없고, 한 모듈에서 여러 실패를 한 번에 보는 편이 낫다.

var failures: Array[String] = []
var checks: int = 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func eq(actual: Variant, expected: Variant, message: String) -> void:
	checks += 1
	if actual != expected:
		failures.append("%s — expected <%s>, got <%s>" % [message, str(expected), str(actual)])

func near(actual: float, expected: float, message: String, tolerance: float = 0.0001) -> void:
	checks += 1
	if absf(actual - expected) > tolerance:
		failures.append("%s — expected ~%f, got %f" % [message, expected, actual])
