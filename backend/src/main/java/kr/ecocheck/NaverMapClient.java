package kr.ecocheck;

import com.google.gson.*;
import java.net.*;
import java.net.http.HttpRequest;
import java.nio.charset.StandardCharsets;
import java.time.Duration;

/** 지도 자체는 iOS SDK가 표시합니다. 이 클래스는 서울시 주소를 좌표로 변환합니다. */
final class NaverMapClient {
  private final String id, secret;
  private final URI endpoint;
  private final ExternalJsonClient http = new ExternalJsonClient();

  NaverMapClient(AppConfig c) {
    this(
        c.naverId(),
        c.naverSecret(),
        URI.create("https://maps.apigw.ntruss.com/map-geocode/v2/geocode"));
  }

  NaverMapClient(String id, String secret, URI endpoint) {
    this.id = id;
    this.secret = secret;
    this.endpoint = endpoint;
  }

  boolean configured() {
    return !id.isBlank() && !secret.isBlank();
  }

  JsonArray geocode(String address) {
    if (!configured())
      throw new ApiException(503, "NAVER_NOT_CONFIGURED", "네이버 지도 Client ID와 Secret을 설정해주세요.");
    var uri = URI.create(endpoint + "?query=" + URLEncoder.encode(address, StandardCharsets.UTF_8));
    var request =
        HttpRequest.newBuilder(uri)
            .timeout(Duration.ofSeconds(12))
            .header("x-ncp-apigw-api-key-id", id)
            .header("x-ncp-apigw-api-key", secret)
            .header("Accept", "application/json")
            .GET()
            .build();
    var json = http.send(request, "NAVER");
    if (!json.has("status")
        || !"OK".equals(json.get("status").getAsString())
        || !json.has("addresses")
        || !json.get("addresses").isJsonArray())
      throw new ApiException(502, "NAVER_INVALID_RESPONSE", "주소 변환 결과가 올바르지 않습니다.");
    return json.getAsJsonArray("addresses");
  }
}
