package kr.ecocheck;

import static org.junit.jupiter.api.Assertions.*;

import com.google.gson.*;
import com.sun.net.httpserver.HttpServer;
import java.awt.image.BufferedImage;
import java.io.*;
import java.net.*;
import java.net.http.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import javax.imageio.ImageIO;
import kr.ecocheck.Models.*;
import org.junit.jupiter.api.*;

/** 외부 공급자의 로컬 HTTP 대역 + 실제 EcoCheck HTTP 서버를 사용한 계약/흐름 테스트. */
class ApiIntegrationTest {
  private HttpServer upstream;
  private EcoCheckHttpServer app;
  private volatile int upstreamStatus = 200;
  private volatile String prediction =
      "{\"categoryId\":\"pet_bottle\",\"needsConfirmation\":false,\"reason\":\"투명 페트병으로 보입니다.\"}";
  private String upstreamBody;
  private String image;
  private final String token = "a".repeat(64), other = "b".repeat(64);
  private final Gson gson = new Gson();
  private final HttpClient http = HttpClient.newHttpClient();
  private GuideService guides;
  private MemoryDb db;

  @BeforeEach
  void start() throws Exception {
    var bytes = new ByteArrayOutputStream();
    ImageIO.write(new BufferedImage(4, 4, BufferedImage.TYPE_INT_RGB), "png", bytes);
    image = Base64.getEncoder().encodeToString(bytes.toByteArray());
    guides = new GuideService();
    db = new MemoryDb();
    upstream = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
    upstream.createContext(
        "/",
        e -> {
          upstreamBody = new String(e.getRequestBody().readAllBytes(), StandardCharsets.UTF_8);
          String response =
              e.getRequestURI().getPath().contains("geocode")
                  ? "{\"status\":\"OK\",\"addresses\":[{\"x\":\"126.9780\",\"y\":\"37.5665\"}]}"
                  : gson.toJson(
                      Map.of(
                          "candidates",
                          List.of(
                              Map.of(
                                  "finishReason",
                                  "STOP",
                                  "content",
                                  Map.of("parts", List.of(Map.of("text", prediction)))))));
          byte[] body = response.getBytes(StandardCharsets.UTF_8);
          e.sendResponseHeaders(upstreamStatus, body.length);
          e.getResponseBody().write(body);
          e.close();
        });
    upstream.start();
    var config =
        new AppConfig(
            "127.0.0.1", 0, "", "", "", "test-key", "test-model", "test-id", "test-secret");
    var client = new GeminiClient("test-key", "test-model", URI.create(base()), guides);
    app =
        new EcoCheckHttpServer(
            new InetSocketAddress("127.0.0.1", 0),
            config,
            db,
            guides,
            new AnalysisService(client, guides));
    app.start();
  }

  @AfterEach
  void stop() {
    if (app != null) app.close();
    if (upstream != null) upstream.stop(0);
  }

  private String base() {
    return "http://127.0.0.1:" + upstream.getAddress().getPort() + "/";
  }

  private HttpResponse<String> call(String method, String path, String body, String auth)
      throws Exception {
    var req =
        HttpRequest.newBuilder(URI.create("http://127.0.0.1:" + app.port() + path))
            .header("Content-Type", "application/json");
    if (auth != null) req.header("Authorization", "Bearer " + auth);
    req.method(
        method,
        body == null
            ? HttpRequest.BodyPublishers.noBody()
            : HttpRequest.BodyPublishers.ofString(body));
    return http.send(req.build(), HttpResponse.BodyHandlers.ofString());
  }

  private String analyze() throws Exception {
    var r =
        call(
            "POST",
            "/api/v1/analyze",
            gson.toJson(Map.of("mimeType", "image/png", "imageBase64", image)),
            token);
    assertEquals(200, r.statusCode(), r.body());
    return JsonParser.parseString(r.body()).getAsJsonObject().get("id").getAsString();
  }

  @Test
  void fullFlowAndOwnerIsolation() throws Exception {
    String id = analyze();
    assertTrue(upstreamBody.contains("inline_data"));
    assertTrue(upstreamBody.contains("responseSchema"));
    String save = gson.toJson(Map.of("analysisId", id, "confirmed", true));
    assertEquals(404, call("POST", "/api/v1/scans", save, other).statusCode());
    assertEquals(200, call("POST", "/api/v1/scans", save, token).statusCode());
    assertEquals(200, call("POST", "/api/v1/scans", save, token).statusCode());
    assertEquals(
        1,
        JsonParser.parseString(call("GET", "/api/v1/scans", null, token).body())
            .getAsJsonObject()
            .get("total")
            .getAsInt());
    assertEquals(
        0,
        JsonParser.parseString(call("GET", "/api/v1/scans", null, other).body())
            .getAsJsonObject()
            .get("total")
            .getAsInt());
    assertEquals(404, call("DELETE", "/api/v1/scans/" + id, null, other).statusCode());
    assertEquals(200, call("DELETE", "/api/v1/scans/" + id, null, token).statusCode());
    assertEquals(404, call("POST", "/api/v1/scans", save, token).statusCode());
  }

  @Test
  void uncertainCannotSave() throws Exception {
    prediction =
        "{\"categoryId\":\"unknown\",\"needsConfirmation\":true,\"reason\":\"재질을 확인할 수 없습니다.\"}";
    String id = analyze();
    assertEquals(
        422,
        call(
                "POST",
                "/api/v1/scans",
                gson.toJson(Map.of("analysisId", id, "confirmed", true)),
                token)
            .statusCode());
  }

  @Test
  void requiresConfirmationAndServerAnalysis() throws Exception {
    String id = analyze();
    assertEquals(
        400,
        call(
                "POST",
                "/api/v1/scans",
                gson.toJson(Map.of("analysisId", id, "confirmed", false)),
                token)
            .statusCode());
    assertEquals(
        400,
        call("POST", "/api/v1/scans", "{\"categoryId\":\"pet_bottle\",\"confidence\":1}", token)
            .statusCode());
  }

  @Test
  void invalidInputsRejected() throws Exception {
    assertEquals(401, call("POST", "/api/v1/analyze", "{}", null).statusCode());
    assertEquals(400, call("POST", "/api/v1/analyze", "{", token).statusCode());
    assertEquals(
        400,
        call(
                "POST",
                "/api/v1/analyze",
                "{\"mimeType\":\"image/png\",\"imageBase64\":\"bad\"}",
                token)
            .statusCode());
    assertEquals(400, call("GET", "/api/v1/scans?limit=101", null, token).statusCode());
    assertEquals(405, call("POST", "/health", "{}", null).statusCode());
    assertEquals(404, call("GET", "/missing", null, null).statusCode());
  }

  @Test
  void mapsFiltersSortsAndRejectsInvalidCoordinates() throws Exception {
    assertEquals(400, call("GET", "/api/v1/bins?lat=NaN&lng=127", null, null).statusCode());
    assertEquals(
        400, call("GET", "/api/v1/bins?lat=37.56&lng=126.97&type=wrong", null, null).statusCode());
    var r = call("GET", "/api/v1/bins?lat=37.5665&lng=126.978&radius=1000", null, null);
    assertEquals(200, r.statusCode());
    var items = JsonParser.parseString(r.body()).getAsJsonObject().getAsJsonArray("items");
    assertEquals(1, items.size());
    assertEquals(0, items.get(0).getAsJsonObject().get("distanceMeters").getAsDouble(), 0.01);
  }

  @Test
  void providerRateLimitAndMalformedOutput() throws Exception {
    upstreamStatus = 429;
    var response =
        call(
            "POST",
            "/api/v1/analyze",
            gson.toJson(Map.of("mimeType", "image/png", "imageBase64", image)),
            token);
    assertEquals(503, response.statusCode());
    assertTrue(response.body().contains("GEMINI_RATE_LIMIT"));
    upstreamStatus = 200;
    prediction = "{\"categoryId\":\"fake\",\"needsConfirmation\":false,\"reason\":\"fake\"}";
    assertEquals(
        502,
        call(
                "POST",
                "/api/v1/analyze",
                gson.toJson(Map.of("mimeType", "image/png", "imageBase64", image)),
                token)
            .statusCode());
  }

  @Test
  void naverProtocolAndAuthError() {
    var client = new NaverMapClient("id", "secret", URI.create(base() + "geocode"));
    assertEquals(1, client.geocode("서울특별시 중구 세종대로 110").size());
    upstreamStatus = 403;
    assertEquals(
        "NAVER_AUTH_FAILED", assertThrows(ApiException.class, () -> client.geocode("서울시청")).code);
  }

  @Test
  void missingKeysAreNotFakeSuccess() {
    assertEquals(
        "GEMINI_NOT_CONFIGURED",
        assertThrows(
                ApiException.class,
                () ->
                    new GeminiClient("", "test", URI.create(base()), guides)
                        .classify("image/png", image))
            .code);
    assertEquals(
        "NAVER_NOT_CONFIGURED",
        assertThrows(
                ApiException.class,
                () -> new NaverMapClient("", "", URI.create(base())).geocode("서울시청"))
            .code);
  }

  @Test
  void healthReflectsDbFailure() throws Exception {
    assertEquals(200, call("GET", "/health", null, null).statusCode());
    db.ready = false;
    assertEquals(503, call("GET", "/health", null, null).statusCode());
  }

  static final class MemoryDb implements ScanRepository {
    final Map<String, Map<String, Scan>> scans = new HashMap<>();
    boolean ready = true;

    public boolean healthy() {
      return ready;
    }

    public Scan save(String owner, Analysis a) {
      return scans
          .computeIfAbsent(owner, k -> new LinkedHashMap<>())
          .computeIfAbsent(
              a.id(),
              k ->
                  new Scan(
                      a.id(),
                      a.categoryId(),
                      a.name(),
                      a.material(),
                      a.source(),
                      a.modelVersion(),
                      "2026-10-23T00:00:00Z"));
    }

    public Page history(String owner, int limit, int offset) {
      var list = new ArrayList<>(scans.getOrDefault(owner, Map.of()).values());
      return new Page(list.stream().skip(offset).limit(limit).toList(), list.size(), limit, offset);
    }

    public boolean delete(String owner, String id) {
      return scans.getOrDefault(owner, new HashMap<>()).remove(id) != null;
    }

    public List<Bin> bins(double lat, double lng, double radius, String type) {
      return List.of(
          new Bin(
              "fixture-only",
              "중구",
              "테스트 주소",
              "실제 시설물 아님",
              "test",
              "general",
              37.5665,
              126.978,
              "2025-11"),
          new Bin("far-fixture", "중구", "테스트", "", "test", "general", 37.9, 127.5, "2025-11"));
    }
  }
}
