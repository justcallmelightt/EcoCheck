package kr.ecocheck;

import com.google.gson.*;
import com.google.gson.stream.JsonReader;
import com.sun.net.httpserver.*;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.sql.SQLException;
import java.util.*;
import java.util.concurrent.*;

/** HTTP 입력/응답만 담당합니다. 변경할 기능은 각 Service 또는 Client로 이동하세요. */
final class EcoCheckHttpServer implements AutoCloseable {
  private final HttpServer server;
  private final ExecutorService workers =
      new ThreadPoolExecutor(
          4,
          8,
          30,
          TimeUnit.SECONDS,
          new ArrayBlockingQueue<>(32),
          new ThreadPoolExecutor.CallerRunsPolicy());
  private final Gson json = new GsonBuilder().serializeNulls().create();
  private final AppConfig config;
  private final ScanRepository db;
  private final GuideService guides;
  private final AnalysisService analyses;
  private final BinService bins;
  private final Map<String, long[]> rates = new HashMap<>();

  EcoCheckHttpServer(
      InetSocketAddress address,
      AppConfig config,
      ScanRepository db,
      GuideService guides,
      AnalysisService analyses)
      throws IOException {
    this.config = config;
    this.db = db;
    this.guides = guides;
    this.analyses = analyses;
    this.bins = new BinService(db);
    server = HttpServer.create(address, 32);
    server.setExecutor(workers);
    server.createContext("/", this::handle);
  }

  void start() {
    server.start();
  }

  int port() {
    return server.getAddress().getPort();
  }

  public void close() {
    server.stop(0);
    workers.shutdownNow();
  }

  private void handle(HttpExchange e) throws IOException {
    try {
      route(e);
    } catch (ApiException x) {
      respond(e, x.status, Map.of("error", Map.of("code", x.code, "message", x.getMessage())));
    } catch (SQLException x) {
      System.err.println("DB 요청 실패: SQLState=" + x.getSQLState());
      respond(
          e,
          503,
          Map.of(
              "error",
              Map.of(
                  "code",
                  "DATABASE_UNAVAILABLE",
                  "message",
                  "MySQL 연결과 schema.sql 실행 여부를 확인해주세요.")));
    } catch (Exception x) {
      System.err.println("요청 실패: " + x.getClass().getSimpleName());
      respond(
          e,
          500,
          Map.of("error", Map.of("code", "INTERNAL_ERROR", "message", "서버에서 요청을 처리하지 못했습니다.")));
    } finally {
      e.close();
    }
  }

  private void route(HttpExchange e) throws Exception {
    String path = e.getRequestURI().getPath();
    if (path.equals("/health")) {
      method(e, "GET");
      boolean ready = db.healthy();
      respond(
          e,
          ready ? 200 : 503,
          Map.of(
              "status",
              ready ? "ok" : "degraded",
              "database",
              ready ? "ready" : "unavailable",
              "geminiConfigured",
              !config.geminiKey().isBlank(),
              "naverConfigured",
              !config.naverId().isBlank() && !config.naverSecret().isBlank(),
              "externalApisTested",
              false));
      return;
    }
    if (path.equals("/api/v1/categories")) {
      method(e, "GET");
      respond(e, 200, guides.all());
      return;
    }
    if (path.equals("/api/v1/map-config")) {
      method(e, "GET");
      respond(
          e,
          200,
          Map.of("clientId", config.naverId(), "platform", "iOS", "service", "Mobile Dynamic Map"));
      return;
    }
    if (path.equals("/api/v1/bins")) {
      method(e, "GET");
      var q = query(e);
      double lat = number(q, "lat"),
          lng = number(q, "lng"),
          radius = q.containsKey("radius") ? number(q, "radius") : 1000;
      var items = bins.nearby(lat, lng, radius, q.getOrDefault("type", "all"));
      respond(
          e,
          200,
          Map.of(
              "items",
              items,
              "count",
              items.size(),
              "source",
              "서울열린데이터광장 OA-15069",
              "sourceDate",
              "2025-11",
              "notice",
              "주소 기준 좌표입니다. 실제 위치와 다를 수 있으며 재활용 가능 품목은 현장 표시를 확인해주세요."));
      return;
    }
    if (path.equals("/api/v1/analyze")) {
      method(e, "POST");
      String owner = owner(e);
      rate(owner);
      var b = body(e, 5_600_000, Set.of("mimeType", "imageBase64"));
      respond(e, 200, analyses.analyze(owner, string(b, "mimeType"), string(b, "imageBase64")));
      return;
    }
    if (path.equals("/api/v1/scans")) {
      String owner = owner(e);
      if (e.getRequestMethod().equals("GET")) {
        var q = query(e);
        int limit = integer(q, "limit", 50, 1, 100), offset = integer(q, "offset", 0, 0, 10000);
        respond(e, 200, db.history(owner, limit, offset));
        return;
      }
      method(e, "POST");
      var b = body(e, 4096, Set.of("analysisId", "confirmed"));
      String id = uuid(string(b, "analysisId"));
      if (!b.has("confirmed")
          || !b.get("confirmed").isJsonPrimitive()
          || !b.get("confirmed").getAsJsonPrimitive().isBoolean()
          || !b.get("confirmed").getAsBoolean())
        throw new ApiException(
            400, "CONFIRMATION_REQUIRED", "분석 결과를 확인한 뒤 confirmed=true로 저장해주세요.");
      respond(e, 200, db.save(owner, analyses.forSave(owner, id)));
      return;
    }
    if (path.startsWith("/api/v1/scans/")) {
      method(e, "DELETE");
      String owner = owner(e), id = uuid(path.substring("/api/v1/scans/".length()));
      if (!db.delete(owner, id)) throw new ApiException(404, "SCAN_NOT_FOUND", "기록이 없습니다.");
      analyses.remove(owner, id);
      respond(e, 200, Map.of("deleted", true));
      return;
    }
    if (path.equals("/api/v1/statistics")) {
      method(e, "GET");
      respond(e, 200, Map.of("totalScans", db.history(owner(e), 1, 0).total()));
      return;
    }
    throw new ApiException(404, "NOT_FOUND", "API 주소를 확인해주세요.");
  }

  private synchronized void rate(String owner) {
    long minute = System.currentTimeMillis() / 60000;
    rates.values().removeIf(v -> v[0] != minute);
    if (!rates.containsKey(owner) && rates.size() >= 1000)
      throw new ApiException(429, "RATE_LIMIT", "요청이 많습니다.");
    var value = rates.computeIfAbsent(owner, k -> new long[] {minute, 0});
    if (++value[1] > 10) throw new ApiException(429, "RATE_LIMIT", "사진 분석은 기기당 분당 10회까지 가능합니다.");
  }

  private String owner(HttpExchange e) throws NoSuchAlgorithmException {
    String auth = e.getRequestHeaders().getFirst("Authorization");
    if (auth == null || !auth.matches("Bearer [0-9a-f]{64}"))
      throw new ApiException(401, "UNAUTHORIZED", "64자리 소문자 16진수 기기 토큰이 필요합니다.");
    return HexFormat.of()
        .formatHex(
            MessageDigest.getInstance("SHA-256")
                .digest(auth.substring(7).getBytes(StandardCharsets.UTF_8)));
  }

  private void method(HttpExchange e, String expected) {
    if (!e.getRequestMethod().equals(expected)) {
      e.getResponseHeaders().set("Allow", expected);
      throw new ApiException(405, "METHOD_NOT_ALLOWED", expected + " 요청을 사용해주세요.");
    }
  }

  private JsonObject body(HttpExchange e, int max, Set<String> allowed) throws IOException {
    String type = e.getRequestHeaders().getFirst("Content-Type");
    if (type == null
        || !type.toLowerCase(Locale.ROOT).split(";", 2)[0].strip().equals("application/json"))
      throw new ApiException(415, "JSON_REQUIRED", "Content-Type: application/json이 필요합니다.");
    byte[] bytes = e.getRequestBody().readNBytes(max + 1);
    if (bytes.length > max) throw new ApiException(413, "BODY_TOO_LARGE", "요청 본문이 너무 큽니다.");
    try {
      JsonReader reader =
          new JsonReader(new StringReader(new String(bytes, StandardCharsets.UTF_8)));
      reader.setStrictness(Strictness.STRICT);
      JsonElement value = JsonParser.parseReader(reader);
      if (reader.peek() != com.google.gson.stream.JsonToken.END_DOCUMENT || !value.isJsonObject())
        throw new JsonSyntaxException("object required");
      var obj = value.getAsJsonObject();
      if (!allowed.containsAll(obj.keySet())) throw new JsonSyntaxException("unknown field");
      return obj;
    } catch (JsonParseException | IllegalStateException | IOException ex) {
      throw new ApiException(400, "INVALID_JSON", "JSON 형식과 필드 이름을 확인해주세요.");
    }
  }

  private String string(JsonObject b, String key) {
    if (!b.has(key)
        || !b.get(key).isJsonPrimitive()
        || !b.get(key).getAsJsonPrimitive().isString()
        || b.get(key).getAsString().isBlank())
      throw new ApiException(400, "INVALID_FIELD", key + " 문자열이 필요합니다.");
    return b.get(key).getAsString();
  }

  private String uuid(String id) {
    try {
      if (!UUID.fromString(id).toString().equals(id)) throw new IllegalArgumentException();
      return id;
    } catch (IllegalArgumentException ex) {
      throw new ApiException(400, "INVALID_ID", "올바른 UUID가 필요합니다.");
    }
  }

  private Map<String, String> query(HttpExchange e) {
    Map<String, String> result = new HashMap<>();
    String raw = e.getRequestURI().getRawQuery();
    if (raw != null)
      try {
        for (String pair : raw.split("&")) {
          var p = pair.split("=", 2);
          String k = URLDecoder.decode(p[0], StandardCharsets.UTF_8);
          if (result.put(k, p.length == 2 ? URLDecoder.decode(p[1], StandardCharsets.UTF_8) : "")
              != null) throw new IllegalArgumentException();
        }
      } catch (IllegalArgumentException ex) {
        throw new ApiException(400, "INVALID_QUERY", "쿼리 형식을 확인해주세요.");
      }
    return result;
  }

  private double number(Map<String, String> q, String key) {
    try {
      return Double.parseDouble(q.get(key));
    } catch (Exception ex) {
      throw new ApiException(400, "INVALID_QUERY", key + " 숫자가 필요합니다.");
    }
  }

  private int integer(Map<String, String> q, String key, int fallback, int min, int max) {
    try {
      int n = q.containsKey(key) ? Integer.parseInt(q.get(key)) : fallback;
      if (n < min || n > max) throw new NumberFormatException();
      return n;
    } catch (NumberFormatException ex) {
      throw new ApiException(400, "INVALID_QUERY", key + " 범위를 확인해주세요.");
    }
  }

  private void respond(HttpExchange e, int status, Object value) throws IOException {
    byte[] bytes = json.toJson(value).getBytes(StandardCharsets.UTF_8);
    e.getResponseHeaders().set("Content-Type", "application/json; charset=utf-8");
    e.getResponseHeaders().set("Cache-Control", "no-store");
    e.getResponseHeaders().set("X-Content-Type-Options", "nosniff");
    e.sendResponseHeaders(status, bytes.length);
    e.getResponseBody().write(bytes);
  }
}
