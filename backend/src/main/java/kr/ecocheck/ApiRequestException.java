package kr.ecocheck;

final class ApiRequestException extends RuntimeException {
    final int status;
    final String code;

    ApiRequestException(int status, String code, String message) {
        super(message);
        this.status = status;
        this.code = code;
    }
}
