package kr.ecocheck;

import com.google.gson.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import kr.ecocheck.Models.Bin;

/** 비용이 발생할 수 있는 외부 호출/데이터 적재는 공개 API가 아닌 로컬 CLI에서만 실행합니다. */
final class AdminCommands {
  static void run(String[] args, AppConfig config, MySqlRepository db) throws Exception {
    if (args[0].equals("--check-naver")) {
      if (args.length != 1) throw new IllegalArgumentException("사용법: --check-naver");
      var naver = new NaverMapClient(config);
      if (!naver.configured())
        throw new ApiException(503, "NAVER_NOT_CONFIGURED", "backend/.env에 NAVER_MAP_CLIENT_ID와 NAVER_MAP_CLIENT_SECRET을 설정해주세요.");
      var addresses = naver.geocode("서울특별시 중구 세종대로 110");
      if (addresses.size() != 1)
        throw new ApiException(502, "NAVER_GEOCODING_UNEXPECTED", "서울시청 주소의 단일 좌표를 확인하지 못했습니다.");
      var address = addresses.get(0).getAsJsonObject();
      System.out.println(new GsonBuilder().setPrettyPrinting().create().toJson(Map.of(
          "status", "PASS", "address", "서울특별시 중구 세종대로 110",
          "latitude", address.get("y").getAsDouble(), "longitude", address.get("x").getAsDouble())));
      return;
    }
    if (args[0].equals("--check-gemini-image")) {
      if (args.length != 2)
        throw new IllegalArgumentException("사용법: --check-gemini-image FILE.jpg|FILE.png");
      if (config.geminiKey().isBlank())
        throw new ApiException(503, "GEMINI_NOT_CONFIGURED", "backend/.env에 GEMINI_API_KEY를 설정해주세요.");
      Path image = Path.of(args[1]);
      if (!Files.isRegularFile(image) || Files.size(image) > 4L * 1024 * 1024)
        throw new IllegalArgumentException("4MiB 이하 JPEG/PNG 파일을 지정해주세요.");
      byte[] bytes = Files.readAllBytes(image);
      String mime = bytes.length >= 3 && (bytes[0] & 0xff) == 0xff
              && (bytes[1] & 0xff) == 0xd8 && (bytes[2] & 0xff) == 0xff
          ? "image/jpeg"
          : bytes.length >= 8 && (bytes[0] & 0xff) == 0x89
              && bytes[1] == 'P' && bytes[2] == 'N' && bytes[3] == 'G'
                  ? "image/png" : "unsupported";
      String encoded = Base64.getEncoder().encodeToString(bytes);
      AnalysisService.validateImage(mime, encoded);
      var prediction = new GeminiClient(config, new GuideService()).classify(mime, encoded);
      System.out.println(new GsonBuilder().setPrettyPrinting().create().toJson(Map.of(
          "model", config.geminiModel(),
          "categoryId", prediction.categoryId(),
          "needsConfirmation", prediction.needsConfirmation(),
          "reason", prediction.reason())));
      return;
    }
    if (args[0].equals("--check-apis")) {
      var results = new LinkedHashMap<String, Object>();
      results.put("database", db.healthy() ? "PASS" : "UNAVAILABLE");
      var naver = new NaverMapClient(config);
      if (!naver.configured()) results.put("naverGeocoding", "SKIPPED: 키 미발급/미설정");
      else
        try {
          results.put(
              "naverGeocoding",
              naver.geocode("서울특별시 중구 세종대로 110").isEmpty() ? "FAIL: 주소 결과 없음" : "PASS");
        } catch (ApiException e) {
          results.put("naverGeocoding", e.code);
        }
      if (config.geminiKey().isBlank()) results.put("gemini", "SKIPPED: 키 미발급/미설정");
      else {
        var http = new ExternalJsonClient();
        try {
          var req =
              java.net.http.HttpRequest.newBuilder(
                      java.net.URI.create(
                          "https://generativelanguage.googleapis.com/v1beta/models/"
                              + config.geminiModel()
                              + ":generateContent"))
                  .timeout(java.time.Duration.ofSeconds(30))
                  .header("Content-Type", "application/json")
                  .header("x-goog-api-key", config.geminiKey())
                  .POST(
                      java.net.http.HttpRequest.BodyPublishers.ofString(
                          "{\"contents\":[{\"parts\":[{\"text\":\"Reply exactly OK\"}]}]}"))
                  .build();
          var response = http.send(req, "GEMINI");
          results.put(
              "gemini",
              response.has("candidates") && !response.getAsJsonArray("candidates").isEmpty()
                  ? "PASS (텍스트 호출만 확인, 사진 정확도는 별도 검증)"
                  : "FAIL: 결과 없음");
        } catch (ApiException e) {
          results.put("gemini", e.code);
        }
      }
      System.out.println(new GsonBuilder().setPrettyPrinting().create().toJson(results));
      return;
    }
    if (args[0].equals("--import-bins") && args.length >= 2) {
      var root =
          JsonParser.parseString(Files.readString(Path.of(args[1]), StandardCharsets.UTF_8))
              .getAsJsonObject();
      var rows = root.getAsJsonArray("items");
      var gson = new Gson();
      int imported = 0, located = 0;
      for (var row : rows) {
        var bin = gson.fromJson(row, Bin.class);
        validate(bin);
        db.upsertBin(bin);
        imported++;
        if (bin.latitude() != null) located++;
      }
      System.out.println(
          "가져오기 완료: " + imported + ", 좌표 있음: " + located + ", 좌표 미준비: " + (imported - located));
      return;
    }
    if (args[0].equals("--geocode-bins") && args.length >= 3) {
      Path input = Path.of(args[1]), output = Path.of(args[2]);
      if (input.toAbsolutePath().normalize().equals(output.toAbsolutePath().normalize()))
        throw new IllegalArgumentException("원본 보존을 위해 출력 파일을 다르게 지정하세요.");
      if (Files.exists(output)) throw new IllegalArgumentException("출력 파일이 이미 있습니다. 새 파일명을 사용하세요.");
      var root =
          JsonParser.parseString(Files.readString(input, StandardCharsets.UTF_8)).getAsJsonObject();
      var naver = new NaverMapClient(config);
      int max = args.length >= 4 ? Integer.parseInt(args[3]) : 10;
      if (max < 1 || max > 10000) throw new IllegalArgumentException("최대 호출 수: 1~10000");
      String district = args.length >= 5 ? args[4] : "";
      Map<String, JsonArray> cache = new HashMap<>();
      int calls = 0, located = 0, ambiguous = 0;
      for (var row : root.getAsJsonArray("items")) {
        var item = row.getAsJsonObject();
        var bin = new Gson().fromJson(item, Bin.class);
        validate(bin);
        if (!district.isEmpty() && !district.equals(bin.district())) continue;
        if (bin.latitude() != null) continue;
        String address = "서울특별시 " + bin.district() + " " + bin.address();
        JsonArray addresses = cache.get(address);
        if (addresses == null) {
          if (calls >= max) continue;
          addresses = naver.geocode(address);
          cache.put(address, addresses);
          calls++;
          Thread.sleep(100);
        }
        // 복수 결과는 임의 선택하지 않습니다. 주소 중심점이므로 실제 시설물 위치 검토가 필요합니다.
        if (addresses.size() != 1) {
          ambiguous++;
          continue;
        }
        var a = addresses.get(0).getAsJsonObject();
        double lat = a.get("y").getAsDouble(), lng = a.get("x").getAsDouble();
        if (!Double.isFinite(lat)
            || !Double.isFinite(lng)
            || lat < 37
            || lat > 38
            || lng < 126
            || lng > 128) {
          ambiguous++;
          continue;
        }
        item.addProperty("latitude", lat);
        item.addProperty("longitude", lng);
        located++;
      }
      Files.writeString(
          output,
          new GsonBuilder().setPrettyPrinting().serializeNulls().create().toJson(root),
          StandardCharsets.UTF_8,
          StandardOpenOption.CREATE_NEW);
      System.out.println(
          "API 호출="
              + calls
              + ", 좌표 생성="
              + located
              + ", 미확정="
              + ambiguous
              + ". 결과 검토 후 --import-bins로 적재하세요.");
      return;
    }
    if (args[0].equals("--geocode-bins-osm") && args.length >= 3) {
      Path input = Path.of(args[1]), output = Path.of(args[2]);
      if (input.toAbsolutePath().normalize().equals(output.toAbsolutePath().normalize()))
        throw new IllegalArgumentException("원본 보존을 위해 출력 파일을 다르게 지정하세요.");
      if (Files.exists(output)) throw new IllegalArgumentException("출력 파일이 이미 있습니다. 새 파일명을 사용하세요.");
      var root = JsonParser.parseString(Files.readString(input, StandardCharsets.UTF_8)).getAsJsonObject();
      int max = args.length >= 4 ? Integer.parseInt(args[3]) : 10;
      if (max < 1 || max > 100) throw new IllegalArgumentException("OSM 시험은 호출 수를 1~100으로 제한합니다.");
      String district = args.length >= 5 ? args[4] : "";
      var geocoder = new OpenStreetMapGeocoder();
      Map<String, Optional<double[]>> cache = new HashMap<>();
      int calls = 0, located = 0, ambiguous = 0;
      for (var row : root.getAsJsonArray("items")) {
        var item = row.getAsJsonObject();
        var bin = new Gson().fromJson(item, Bin.class);
        validate(bin);
        if ((!district.isEmpty() && !district.equals(bin.district())) || bin.latitude() != null) continue;
        String address = "서울특별시 " + bin.district() + " " + bin.address();
        Optional<double[]> point = cache.get(address);
        if (point == null) {
          if (calls >= max) continue;
          point = geocoder.geocode(address);
          if (point.isPresent()) cache.put(address, point);
          calls++;
        }
        if (point.isEmpty()) { ambiguous++; continue; }
        item.addProperty("latitude", point.get()[0]);
        item.addProperty("longitude", point.get()[1]);
        located++;
      }
      Files.writeString(output, new GsonBuilder().setPrettyPrinting().serializeNulls().create().toJson(root),
          StandardCharsets.UTF_8, StandardOpenOption.CREATE_NEW);
      System.out.println("OSM API 호출=" + calls + ", 좌표 생성=" + located + ", 미확정=" + ambiguous
          + ". 결과를 검토한 뒤 --import-bins로 적재하세요.");
      return;
    }
    throw new IllegalArgumentException(
        "명령: --check-apis | --check-naver | --check-gemini-image FILE.jpg | --import-bins FILE.json | --geocode-bins INPUT.json OUTPUT.json | --geocode-bins-osm INPUT.json OUTPUT.json"
            + " [최대호출수=10] [자치구]");
  }

  private static void validate(Bin b) {
    if (b.id() == null
        || !b.id().matches("seoul-202511-[0-9]+")
        || b.district() == null
        || b.address() == null
        || b.address().isBlank()
        || b.detail() == null
        || b.locationType() == null
        || !Set.of("general", "recycling", "unknown").contains(b.wasteType())
        || !"2025-11".equals(b.sourceDate())) throw new IllegalArgumentException("잘못된 쓰레기통 데이터");
    if ((b.latitude() == null) != (b.longitude() == null))
      throw new IllegalArgumentException("좌표 쌍 필요");
    if (b.latitude() != null
        && (!Double.isFinite(b.latitude())
            || !Double.isFinite(b.longitude())
            || b.latitude() < 37
            || b.latitude() > 38
            || b.longitude() < 126
            || b.longitude() > 128)) throw new IllegalArgumentException("서울 주변 좌표 필요");
  }
}
