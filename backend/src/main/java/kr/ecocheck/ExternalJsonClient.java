package kr.ecocheck;

import com.google.gson.*;
import java.io.*;
import java.net.http.*;
import java.nio.ByteBuffer;
import java.time.Duration;
import java.util.List;
import java.util.concurrent.*;

/** 외부 호출의 시간/응답 크기를 제한하고 비밀키나 원문 응답을 로그에 남기지 않습니다. */
final class ExternalJsonClient {
  private final HttpClient client =
      HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(8)).build();

  JsonObject send(HttpRequest request, String provider) {
    try {
      var response = sendWithRetry(request, provider);
      byte[] bytes = response.body();
      if (response.statusCode() != 200) {
        int status = response.statusCode();
        if (status == 429)
          throw new ApiException(503, provider + "_RATE_LIMIT", "외부 API 사용량 한도를 확인해주세요.");
        if (status == 401 || status == 403)
          throw new ApiException(503, provider + "_AUTH_FAILED", "외부 API 키와 서비스 권한을 확인해주세요.");
        if (status == 503)
          throw new ApiException(503, provider + "_UNAVAILABLE",
              "AI 분석 서비스를 일시적으로 사용할 수 없습니다. 잠시 후 다시 시도하거나 기본 분리배출 안내를 확인해주세요.");
        throw new ApiException(502, provider + "_HTTP_ERROR", "외부 API 응답 오류 (HTTP " + status + ")");
      }
      if (bytes.length > 1_048_576)
        throw new ApiException(502, provider + "_INVALID_RESPONSE", "외부 API 응답이 너무 큽니다.");
      return JsonParser.parseString(new String(bytes, java.nio.charset.StandardCharsets.UTF_8))
          .getAsJsonObject();
    } catch (HttpTimeoutException e) {
      throw new ApiException(504, provider + "_TIMEOUT", "외부 API 응답 시간이 초과되었습니다.");
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      throw new ApiException(503, provider + "_INTERRUPTED", "요청이 중단되었습니다.");
    } catch (IOException e) {
      throw new ApiException(502, provider + "_CONNECTION_FAILED", "외부 API 네트워크 연결을 확인해주세요.");
    } catch (JsonParseException | IllegalStateException e) {
      throw new ApiException(502, provider + "_INVALID_RESPONSE", "외부 API 응답 형식이 올바르지 않습니다.");
    }
  }

  /** 명시적으로 받은 Gemini 503만 최대 두 번 재시도합니다. 전체 시간은 원래 제한을 유지합니다. */
  private HttpResponse<byte[]> sendWithRetry(HttpRequest request, String provider)
      throws IOException, InterruptedException {
    long budget = request.timeout().orElse(Duration.ofSeconds(30)).toNanos();
    long started = System.nanoTime();
    for (int attempt = 0; ; attempt++) {
      long remaining = budget - (System.nanoTime() - started);
      if (remaining <= 0) throw new HttpTimeoutException("External request deadline exceeded");
      var bounded = HttpRequest.newBuilder(request, (name, value) -> true)
          .timeout(Duration.ofNanos(remaining)).build();
      var response = client.send(bounded, info -> new LimitedBodySubscriber());
      if (!provider.equals("GEMINI") || response.statusCode() != 503 || attempt >= 2)
        return response;
      long delayMillis = 500L << attempt;
      if (budget - (System.nanoTime() - started) <= Duration.ofMillis(delayMillis + 100).toNanos())
        return response;
      Thread.sleep(delayMillis);
    }
  }

  /** 헤더 수신 후 본문도 전체 요청 시간 제한 안에서 읽으며 큰 응답은 즉시 취소합니다. */
  private static final class LimitedBodySubscriber implements HttpResponse.BodySubscriber<byte[]> {
    private final CompletableFuture<byte[]> body = new CompletableFuture<>();
    private final ByteArrayOutputStream bytes = new ByteArrayOutputStream();
    private Flow.Subscription subscription;

    public CompletionStage<byte[]> getBody() {
      return body;
    }

    public void onSubscribe(Flow.Subscription value) {
      subscription = value;
      subscription.request(1);
    }

    public void onNext(List<ByteBuffer> buffers) {
      for (ByteBuffer buffer : buffers) {
        if (bytes.size() + buffer.remaining() > 1_048_576) {
          subscription.cancel();
          body.completeExceptionally(new IOException("External response too large"));
          return;
        }
        byte[] chunk = new byte[buffer.remaining()];
        buffer.get(chunk);
        bytes.writeBytes(chunk);
      }
      subscription.request(1);
    }

    public void onError(Throwable error) {
      body.completeExceptionally(error);
    }

    public void onComplete() {
      body.complete(bytes.toByteArray());
    }
  }
}
