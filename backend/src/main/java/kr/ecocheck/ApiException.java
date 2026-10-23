package kr.ecocheck;

/** HTTP 응답으로 전달할 예상 가능한 오류. 외부 서비스의 원문/키는 포함하지 않습니다. */
final class ApiException extends RuntimeException {
  final int status;
  final String code;

  ApiException(int status, String code, String message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}
