package kr.ecocheck;

import com.google.gson.*;
import com.google.gson.stream.JsonReader;
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import java.io.*;
import java.net.InetSocketAddress;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.sql.SQLException;
import java.util.*;
import java.util.concurrent.*;
import kr.ecocheck.Models.ScanInput;

final class ApiServer implements AutoCloseable {
    private final Store store;
    private final HttpServer server;
    private final ExecutorService workers = new ThreadPoolExecutor(4, 8, 30, TimeUnit.SECONDS,
            new ArrayBlockingQueue<>(64), new ThreadPoolExecutor.CallerRunsPolicy());
    private final Gson json = new Gson();
    private final Set<String> categoryIds;

    ApiServer(InetSocketAddress address, Store store) throws IOException {
        this.store = store;
        categoryIds = new HashSet<>();
        for (var guide : Catalog.load()) categoryIds.add(guide.id());
        server = HttpServer.create(address, 64);
        server.createContext("/", this::handle);
        server.setExecutor(workers);
    }

    void start() { server.start(); }
    int port() { return server.getAddress().getPort(); }
    public void close() { server.stop(1); workers.shutdownNow(); }

    private void handle(HttpExchange exchange) throws IOException {
        try {
            route(exchange);
        } catch (ApiException e) {
            respond(exchange, e.status, Map.of("error", Map.of("code", e.code, "message", e.getMessage())));
        } catch (SQLException e) {
            System.err.println("Database request failed; SQL state=" + e.getSQLState());
            respond(exchange, 503, Map.of("error", Map.of("code", "DATABASE_UNAVAILABLE", "message", "데이터베이스 연결을 확인해주세요.")));
        } catch (Exception e) {
            System.err.println("Request failed: " + e.getClass().getSimpleName());
            respond(exchange, 500, Map.of("error", Map.of("code", "INTERNAL_ERROR", "message", "요청을 처리하지 못했습니다.")));
        } finally {
            exchange.close();
        }
    }

    private void route(HttpExchange e) throws Exception {
        String path = e.getRequestURI().getPath();
        String method = e.getRequestMethod();
        if (path.equals("/health")) {
            requireMethod(e, "GET");
            boolean ready = store.healthy();
            respond(e, ready ? 200 : 503, Map.of("status", ready ? "ok" : "unavailable", "database", ready ? "connected" : "unavailable"));
        } else if (path.equals("/api/v1/categories")) {
            requireMethod(e, "GET"); respond(e, 200, Map.of("items", store.guides()));
        } else if (path.equals("/api/v1/scans")) {
            requireMethod(e, "GET", "POST");
            String owner = owner(e);
            if (method.equals("GET")) {
                var query = query(e);
                if (!Set.of("limit", "offset").containsAll(query.keySet())) throw bad("알 수 없는 조회 조건입니다.");
                respond(e, 200, store.scans(owner, integer(query, "limit", 50, 1, 100), integer(query, "offset", 0, 0, 10000)));
            } else {
                ScanInput input = parseInput(e);
                var result = store.save(owner, input);
                respond(e, result.created() ? 201 : 200, result.scan());
            }
        } else if (path.equals("/api/v1/statistics")) {
            requireMethod(e, "GET"); respond(e, 200, store.statistics(owner(e)));
        } else if (path.startsWith("/api/v1/scans/")) {
            requireMethod(e, "DELETE");
            String owner = owner(e);
            String id = uuid(path.substring("/api/v1/scans/".length()));
            if (!store.delete(owner, id)) throw new ApiException(404, "NOT_FOUND", "기록을 찾을 수 없습니다.");
            respond(e, 200, Map.of("deleted", true));
        } else {
            throw new ApiException(404, "NOT_FOUND", "주소를 확인해주세요.");
        }
    }

    private ScanInput parseInput(HttpExchange e) throws IOException {
        String type = e.getRequestHeaders().getFirst("Content-Type");
        if (type == null || !type.split(";", 2)[0].strip().equalsIgnoreCase("application/json"))
            throw new ApiException(415, "JSON_REQUIRED", "application/json 형식으로 보내주세요.");
        byte[] bytes = e.getRequestBody().readNBytes(4097);
        if (bytes.length > 4096) throw new ApiException(413, "BODY_TOO_LARGE", "요청은 4096바이트 이하로 보내주세요.");
        try {
            JsonReader reader = new JsonReader(new InputStreamReader(new ByteArrayInputStream(bytes), StandardCharsets.UTF_8));
            reader.setStrictness(Strictness.STRICT);
            // Read keys explicitly so duplicate fields and unknown fields cannot be silently overwritten.
            reader.beginObject();
            Set<String> keys = new HashSet<>();
            JsonObject body = new JsonObject();
            while (reader.hasNext()) {
                String key = reader.nextName();
                if (!keys.add(key) || !Set.of("id", "categoryId", "confidence", "modelVersion").contains(key)) throw bad("중복되거나 알 수 없는 필드입니다.");
                body.add(key, JsonParser.parseReader(reader));
            }
            reader.endObject();
            if (reader.peek() != com.google.gson.stream.JsonToken.END_DOCUMENT || keys.size() != 4) throw bad("필수 필드를 확인해주세요.");
            String id = uuid(string(body, "id"));
            String category = string(body, "categoryId");
            if (!categoryIds.contains(category)) throw bad("지원하지 않는 분류입니다.");
            var confidenceValue = body.get("confidence");
            if (!confidenceValue.isJsonPrimitive() || !confidenceValue.getAsJsonPrimitive().isNumber()) throw bad("confidence는 숫자여야 합니다.");
            double confidence = confidenceValue.getAsDouble();
            if (!Double.isFinite(confidence) || confidence < 0.7 || confidence > 1) throw bad("신뢰도 0.7~1의 결과만 저장할 수 있습니다.");
            String version = string(body, "modelVersion");
            if (!version.matches("[A-Za-z0-9][A-Za-z0-9._-]{0,79}")) throw bad("모델 버전을 확인해주세요.");
            return new ScanInput(id, category, confidence, version);
        } catch (JsonParseException | IllegalStateException | NumberFormatException | IOException ex) {
            throw bad("JSON 요청 형식을 확인해주세요.");
        }
    }

    private String string(JsonObject body, String key) {
        var value = body.get(key);
        if (value == null || !value.isJsonPrimitive() || !value.getAsJsonPrimitive().isString()) throw bad(key + "는 문자열이어야 합니다.");
        return value.getAsString();
    }

    private String uuid(String id) {
        if (!id.matches("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")) throw bad("기록 ID는 UUID여야 합니다.");
        return UUID.fromString(id).toString();
    }

    private String owner(HttpExchange e) throws Exception {
        String header = e.getRequestHeaders().getFirst("Authorization");
        if (header == null || !header.matches("Bearer [0-9a-f]{64}")) {
            e.getResponseHeaders().set("WWW-Authenticate", "Bearer");
            throw new ApiException(401, "TOKEN_REQUIRED", "기기 토큰이 필요합니다.");
        }
        return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(header.substring(7).getBytes(StandardCharsets.US_ASCII)));
    }

    private Map<String, String> query(HttpExchange e) {
        Map<String, String> result = new HashMap<>();
        String raw = e.getRequestURI().getRawQuery();
        if (raw == null || raw.isEmpty()) return result;
        try {
            for (String part : raw.split("&")) {
                String[] pair = part.split("=", 2);
                if (pair.length != 2) throw bad("조회 조건을 확인해주세요.");
                String key = URLDecoder.decode(pair[0], StandardCharsets.UTF_8);
                if (result.put(key, URLDecoder.decode(pair[1], StandardCharsets.UTF_8)) != null) throw bad("중복 조회 조건입니다.");
            }
        } catch (IllegalArgumentException ex) { throw bad("조회 조건을 확인해주세요."); }
        return result;
    }

    private int integer(Map<String, String> query, String key, int fallback, int min, int max) {
        String value = query.get(key);
        if (value == null) return fallback;
        try {
            if (!value.matches("[0-9]{1,5}")) throw bad("조회 범위를 확인해주세요.");
            int result = Integer.parseInt(value);
            if (result < min || result > max) throw bad("조회 범위를 확인해주세요.");
            return result;
        } catch (NumberFormatException ex) { throw bad("조회 범위를 확인해주세요."); }
    }

    private void requireMethod(HttpExchange e, String... methods) {
        if (!Arrays.asList(methods).contains(e.getRequestMethod())) {
            e.getResponseHeaders().set("Allow", String.join(", ", methods));
            throw new ApiException(405, "METHOD_NOT_ALLOWED", "요청 방식을 확인해주세요.");
        }
    }
    private ApiException bad(String message) { return new ApiException(400, "INVALID_REQUEST", message); }
    private void respond(HttpExchange e, int status, Object data) throws IOException {
        byte[] body = json.toJson(data).getBytes(StandardCharsets.UTF_8);
        e.getResponseHeaders().set("Content-Type", "application/json; charset=utf-8");
        e.getResponseHeaders().set("Cache-Control", "no-store");
        e.getResponseHeaders().set("X-Content-Type-Options", "nosniff");
        e.sendResponseHeaders(status, body.length);
        e.getResponseBody().write(body);
    }
}
