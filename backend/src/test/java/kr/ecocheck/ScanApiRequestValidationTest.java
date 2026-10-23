package kr.ecocheck;

import static org.junit.jupiter.api.Assertions.*;
import com.google.gson.JsonParser;
import java.net.*;
import java.net.http.*;
import java.util.*;
import kr.ecocheck.ScanDataModels.*;
import org.junit.jupiter.api.*;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

class ScanApiRequestValidationTest {
    private EcoCheckHttpServer server;
    private final HttpClient client = HttpClient.newHttpClient();
    private final String token = "a".repeat(64);
    private static final String VALID =
            "{\"id\":\"12345678-1234-1234-1234-123456789012\",\"categoryId\":\"pet_bottle\",\"confidence\":0.9,\"modelVersion\":\"1.0\"}";

    @BeforeEach
    void start() throws Exception {
        server =
                new EcoCheckHttpServer(
                        new InetSocketAddress("127.0.0.1", 0),
                        new ScanRecordRepository() {
                            public boolean healthy() {
                                return true;
                            }

                            public List<Guide> guides() {
                                return List.of();
                            }

                            public SaveResult save(String hash, ScanInput input) {
                                assertEquals(64, hash.length());
                                assertNotEquals(token, hash);

                                return new SaveResult(
                                        new Scan(
                                                input.id(),
                                                input.categoryId(),
                                                "투명 페트병",
                                                "PET",
                                                input.confidence(),
                                                input.modelVersion(),
                                                "2026-10-22T00:00:00Z"),
                                        true);
                            }

                            public ScanPage scans(String hash, int limit, int offset) {
                                return new ScanPage(List.of(), 0, limit, offset);
                            }

                            public Statistics statistics(String hash) {
                                return new Statistics(0);
                            }

                            public boolean delete(String hash, String id) {
                                return false;
                            }
                        });
        server.start();
    }

    @AfterEach
    void stop() {
        server.close();
    }

    HttpResponse<String> request(String method, String path, String body, String auth, String type)
            throws Exception {
        var builder =
                HttpRequest.newBuilder(URI.create("http://127.0.0.1:" + server.port() + path));

        if (auth != null)
            builder.header("Authorization", "Bearer " + auth);

        if (type != null)
            builder.header("Content-Type", type);

        return client.send(
                builder.method(
                                method,
                                body == null
                                        ? HttpRequest.BodyPublishers.noBody()
                                        : HttpRequest.BodyPublishers.ofString(body))
                        .build(),
                HttpResponse.BodyHandlers.ofString());
    }

    @Test
    void savesValidResultAndKeepsKoreanUtf8() throws Exception {
        var response =
                request("POST", "/api/v1/scans", VALID, token, "application/json; charset=utf-8");
        assertEquals(201, response.statusCode());
        assertEquals(
                "투명 페트병",
                JsonParser.parseString(response.body())
                        .getAsJsonObject()
                        .get("name")
                        .getAsString());
        assertEquals("no-store", response.headers().firstValue("Cache-Control").orElseThrow());
    }

    @ParameterizedTest
    @ValueSource(
            strings = {
                "{}",
                "null",
                "[]",
                "broken",
                "{\"id\":1}",
                "{\"id\":\"x\",\"categoryId\":\"pet_bottle\",\"confidence\":0.9,\"modelVersion\":\"1\"}",
                "{\"id\":\"12345678-1234-1234-1234-123456789012\",\"categoryId\":null,\"confidence\":0.9,\"modelVersion\":\"1\"}"
            })
    void rejectsMalformedBodies(String body) throws Exception {
        assertEquals(
                400,
                request("POST", "/api/v1/scans", body, token, "application/json").statusCode());
    }

    @Test
    void rejectsInvalidConfidenceCategoryAndExtraFields() throws Exception {
        for (String value :
                List.of("-1", "0.69", "1.1", "1e9999", "null", "\"0.9\"", "true", "NaN")) {
            assertEquals(
                    400,
                    request(
                                    "POST",
                                    "/api/v1/scans",
                                    VALID.replace("0.9", value),
                                    token,
                                    "application/json")
                            .statusCode(),
                    value);
        }

        for (String value : List.of("unknown", "pet_bottle' OR 1=1 --")) {
            assertEquals(
                    400,
                    request(
                                    "POST",
                                    "/api/v1/scans",
                                    VALID.replace("pet_bottle", value),
                                    token,
                                    "application/json")
                            .statusCode());
        }
        assertEquals(
                400,
                request(
                                "POST",
                                "/api/v1/scans",
                                VALID.replace("0.9", "0.9,\"confidence\":0.99"),
                                token,
                                "application/json")
                        .statusCode());
        assertEquals(
                400,
                request(
                                "POST",
                                "/api/v1/scans",
                                VALID.replace("0.9", "0.9,\"photo\":\"secret\""),
                                token,
                                "application/json")
                        .statusCode());
        assertEquals(
                400,
                request("POST", "/api/v1/scans", VALID + "{}", token, "application/json")
                        .statusCode());
    }

    @Test
    void requiresTokenAndJsonAndBoundsBodySize() throws Exception {
        assertEquals(401, request("GET", "/api/v1/scans", null, null, null).statusCode());
        assertEquals(401, request("GET", "/api/v1/scans", null, "bad-token", null).statusCode());
        assertEquals(
                415, request("POST", "/api/v1/scans", VALID, token, "text/plain").statusCode());
        assertEquals(
                413,
                request("POST", "/api/v1/scans", "x".repeat(4097), token, "application/json")
                        .statusCode());
    }

    @Test
    void validatesPaginationPathsAndMethods() throws Exception {
        for (String query :
                List.of(
                        "limit=0",
                        "limit=101",
                        "offset=-1",
                        "offset=10001",
                        "limit=2&limit=3",
                        "limit=abc",
                        "other=1")) {
            assertEquals(
                    400,
                    request("GET", "/api/v1/scans?" + query, null, token, null).statusCode(),
                    query);
        }
        assertEquals(
                200,
                request("GET", "/api/v1/scans?limit=1&offset=2", null, token, null).statusCode());
        assertEquals(404, request("GET", "/api/v1/scans-typo", null, token, null).statusCode());
        var wrongMethod = request("PUT", "/api/v1/scans", VALID, token, "application/json");
        assertEquals(405, wrongMethod.statusCode());
        assertEquals("GET, POST", wrongMethod.headers().firstValue("Allow").orElseThrow());
    }

    @Test
    void bundledCatalogHasUniqueUsableLabels() throws Exception {
        var guides = RecyclingGuideLoader.load();
        assertEquals(5, guides.size());
        assertEquals(guides.size(), guides.stream().map(Guide::id).distinct().count());

        for (Guide guide : guides) {
            assertTrue(guide.id().matches("[a-z_]+"));
            assertFalse(guide.steps().isEmpty());
            assertFalse(guide.note().isBlank());
        }
    }
}
