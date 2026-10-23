package kr.ecocheck;

import static org.junit.jupiter.api.Assertions.*;
import com.sun.net.httpserver.HttpServer;
import java.net.*;
import java.net.http.*;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.*;

class ExternalJsonClientTest {
  private HttpServer server;
  private final AtomicInteger calls = new AtomicInteger();
  private int errorStatus = 503;
  private int errorsBeforeSuccess = Integer.MAX_VALUE;

  @BeforeEach void start() throws Exception {
    server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
    server.createContext("/", exchange -> {
      exchange.getRequestBody().readAllBytes();
      int status = calls.incrementAndGet() <= errorsBeforeSuccess ? errorStatus : 200;
      byte[] body = "{\"ok\":true}".getBytes(StandardCharsets.UTF_8);
      exchange.sendResponseHeaders(status, body.length);
      exchange.getResponseBody().write(body);
      exchange.close();
    });
    server.start();
  }

  @AfterEach void stop() { server.stop(0); }

  private HttpRequest request() {
    return HttpRequest.newBuilder(URI.create("http://127.0.0.1:" + server.getAddress().getPort() + "/"))
        .timeout(Duration.ofSeconds(5))
        .POST(HttpRequest.BodyPublishers.ofString("{}"))
        .build();
  }

  @Test void recoversAfterTemporary503() {
    errorsBeforeSuccess = 1;
    assertTrue(new ExternalJsonClient().send(request(), "GEMINI").get("ok").getAsBoolean());
    assertEquals(2, calls.get());
  }

  @Test void persistent503StopsAfterThreeAttempts() {
    ApiException error = assertThrows(ApiException.class,
        () -> new ExternalJsonClient().send(request(), "GEMINI"));
    assertEquals(503, error.status);
    assertEquals("GEMINI_UNAVAILABLE", error.code);
    assertEquals(3, calls.get());
  }

  @Test void permissionErrorsAreNotRetried() {
    errorStatus = 403;
    assertEquals("GEMINI_AUTH_FAILED", assertThrows(ApiException.class,
        () -> new ExternalJsonClient().send(request(), "GEMINI")).code);
    assertEquals(1, calls.get());
  }

  @Test void quotaErrorsAreNotRetried() {
    errorStatus = 429;
    assertEquals("GEMINI_RATE_LIMIT", assertThrows(ApiException.class,
        () -> new ExternalJsonClient().send(request(), "GEMINI")).code);
    assertEquals(1, calls.get());
  }
}
