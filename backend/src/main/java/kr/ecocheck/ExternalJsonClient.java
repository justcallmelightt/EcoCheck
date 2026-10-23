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
      var response = client.send(request, info -> new LimitedBodySubscriber());
      byte[] bytes = response.body();
      if (response.statusCode() != 200) {
        int status = response.statusCode();
        if (status == 429)
          throw new ApiException(503, provider + "_RATE_LIMIT", "외부 API 사용량 한도를 확인해주세요.");
        if (status == 401 || status == 403)
          throw new ApiException(503, provider + "_AUTH_FAILED", "외부 API 키와 서비스 권한을 확인해주세요.");
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
