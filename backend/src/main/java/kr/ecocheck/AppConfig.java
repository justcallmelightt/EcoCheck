package kr.ecocheck;

import java.io.IOException;
import java.nio.file.*;
import java.util.*;

/** IntelliJ 작업 디렉터리가 루트 또는 backend여도 같은 설정을 읽습니다. 환경변수가 우선합니다. */
record AppConfig(
    String host,
    int port,
    String dbUrl,
    String dbUser,
    String dbPassword,
    String geminiKey,
    String geminiModel,
    String naverId,
    String naverSecret) {
  static AppConfig load() throws IOException {
    Map<String, String> v = new HashMap<>();
    Path file = Files.exists(Path.of(".env")) ? Path.of(".env") : Path.of("backend/.env");
    if (Files.exists(file))
      for (String line : Files.readAllLines(file)) {
        line = line.strip();
        if (line.isEmpty() || line.startsWith("#")) continue;
        int i = line.indexOf('=');
        if (i < 1) throw new IllegalArgumentException("잘못된 .env 형식");
        String value = line.substring(i + 1).strip();
        if (value.length() > 1
            && ((value.startsWith("\"") && value.endsWith("\""))
                || (value.startsWith("'") && value.endsWith("'"))))
          value = value.substring(1, value.length() - 1);
        v.put(line.substring(0, i).strip(), value);
      }
    v.putAll(System.getenv());
    int port = Integer.parseInt(v.getOrDefault("ECOCHECK_PORT", "8080"));
    if (port < 1 || port > 65535) throw new IllegalArgumentException("포트 범위: 1~65535");
    String model = v.getOrDefault("GEMINI_MODEL", "gemini-3.8-flash");
    if (!model.matches("[a-zA-Z0-9._-]{1,100}")) throw new IllegalArgumentException("잘못된 모델 이름");
    return new AppConfig(
        v.getOrDefault("ECOCHECK_HOST", "127.0.0.1"),
        port,
        v.getOrDefault(
            "ECOCHECK_DB_URL",
            "jdbc:mysql://127.0.0.1:3306/ecocheck?characterEncoding=UTF-8&connectionTimeZone=UTC&connectTimeout=3000&socketTimeout=5000"),
        v.getOrDefault("ECOCHECK_DB_USER", "ecocheck"),
        v.getOrDefault("ECOCHECK_DB_PASSWORD", ""),
        v.getOrDefault("GEMINI_API_KEY", ""),
        model,
        v.getOrDefault("NAVER_MAP_CLIENT_ID", ""),
        v.getOrDefault("NAVER_MAP_CLIENT_SECRET", ""));
  }
}
