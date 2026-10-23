package kr.ecocheck;

import static org.junit.jupiter.api.Assertions.*;
import static org.junit.jupiter.api.Assumptions.assumeTrue;
import com.google.gson.*;
import java.net.*;
import java.net.http.*;
import java.util.*;
import org.junit.jupiter.api.Test;

class MySqlScanRecordIntegrationTest {
    @Test
    void persistsAcrossRestartAndIsolatesDevicesWithIdempotentSaves() throws Exception {
        String url = System.getenv("ECOCHECK_TEST_DB_URL");
        assumeTrue(
                url != null && !url.isBlank(),
                "Set ECOCHECK_TEST_DB_* to run against a separate MySQL database");
        ServerDatabaseConfig config =
                new ServerDatabaseConfig(
                        "127.0.0.1",
                        0,
                        url,
                        System.getenv("ECOCHECK_TEST_DB_USER"),
                        System.getenv("ECOCHECK_TEST_DB_PASSWORD"));
        MySqlScanRecordRepository store = new MySqlScanRecordRepository(config);
        store.initialize();
        store.initialize();
        String ownerA = randomToken(), ownerB = randomToken();
        String id = UUID.randomUUID().toString();
        String id2 = UUID.randomUUID().toString();

        String body =
                "{\"id\":\""
                        + id
                        + "\",\"categoryId\":\"pet_bottle\",\"confidence\":0.95,\"modelVersion\":\"test-1\"}";

        try (EcoCheckHttpServer server =
                new EcoCheckHttpServer(new InetSocketAddress("127.0.0.1", 0), store)) {
            server.start();
            assertEquals(200, call(server, "GET", "/health", null, null).statusCode());
            var categories =
                    json(call(server, "GET", "/api/v1/categories", null, null))
                            .getAsJsonArray("items");
            assertEquals(5, categories.size());
            assertTrue(categories.toString().contains("투명 페트병"));
            assertEquals(201, call(server, "POST", "/api/v1/scans", body, ownerA).statusCode());
            var firstPage = json(call(server, "GET", "/api/v1/scans", null, ownerA));
            String createdAt =
                    firstPage
                            .getAsJsonArray("items")
                            .get(0)
                            .getAsJsonObject()
                            .get("createdAt")
                            .getAsString();
            assertTrue(
                    java.time.Duration.between(
                                            java.time.Instant.parse(createdAt),
                                            java.time.Instant.now())
                                    .abs()
                                    .toSeconds()
                            < 10);
            assertEquals(200, call(server, "POST", "/api/v1/scans", body, ownerA).statusCode());
            assertEquals(
                    409,
                    call(server, "POST", "/api/v1/scans", body.replace("0.95", "0.8"), ownerA)
                            .statusCode());
            assertEquals(
                    201,
                    call(server, "POST", "/api/v1/scans", body.replace(id, id2), ownerA)
                            .statusCode());
            var page = json(call(server, "GET", "/api/v1/scans?limit=1&offset=1", null, ownerA));
            assertEquals(2, page.get("total").getAsLong());
            assertEquals(1, page.getAsJsonArray("items").size());
            assertEquals(
                    id,
                    page.getAsJsonArray("items").get(0).getAsJsonObject().get("id").getAsString());
            assertEquals(
                    0,
                    json(call(server, "GET", "/api/v1/statistics", null, ownerB))
                            .get("totalScans")
                            .getAsLong());
            assertEquals(
                    404, call(server, "DELETE", "/api/v1/scans/" + id, null, ownerB).statusCode());
        }
        // New server and repository instance must still see the rows in MySQL.
        try (EcoCheckHttpServer restarted =
                new EcoCheckHttpServer(
                        new InetSocketAddress("127.0.0.1", 0),
                        new MySqlScanRecordRepository(config))) {
            restarted.start();
            assertEquals(
                    2,
                    json(call(restarted, "GET", "/api/v1/statistics", null, ownerA))
                            .get("totalScans")
                            .getAsLong());
            assertEquals(
                    200,
                    call(restarted, "DELETE", "/api/v1/scans/" + id, null, ownerA).statusCode());
            assertEquals(
                    200,
                    call(restarted, "DELETE", "/api/v1/scans/" + id2, null, ownerA).statusCode());
            assertEquals(
                    0,
                    json(call(restarted, "GET", "/api/v1/statistics", null, ownerA))
                            .get("totalScans")
                            .getAsLong());
        }
    }

    private String randomToken() {
        return UUID.randomUUID().toString().replace("-", "")
                + UUID.randomUUID().toString().replace("-", "");
    }

    private JsonObject json(HttpResponse<String> response) {
        return JsonParser.parseString(response.body()).getAsJsonObject();
    }

    private HttpResponse<String> call(
            EcoCheckHttpServer server, String method, String path, String body, String token)
            throws Exception {
        var builder =
                HttpRequest.newBuilder(URI.create("http://127.0.0.1:" + server.port() + path))
                        .header("Content-Type", "application/json");

        if (token != null)
            builder.header("Authorization", "Bearer " + token);

        return HttpClient.newHttpClient()
                .send(
                        builder.method(
                                        method,
                                        body == null
                                                ? HttpRequest.BodyPublishers.noBody()
                                                : HttpRequest.BodyPublishers.ofString(body))
                                .build(),
                        HttpResponse.BodyHandlers.ofString());
    }
}
