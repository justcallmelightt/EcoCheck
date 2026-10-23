package kr.ecocheck;

import com.google.gson.JsonArray;
import com.google.gson.JsonParser;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.Optional;

/** Low-volume offline geocoding helper. Not used by the app's public request path. */
final class OpenStreetMapGeocoder {
  private static final URI ENDPOINT = URI.create("https://nominatim.openstreetmap.org/search");
  private final HttpClient client = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();
  private long lastRequestAt;

  Optional<double[]> geocode(String query) throws Exception {
    long wait = 1_100 - (System.currentTimeMillis() - lastRequestAt);
    if (lastRequestAt != 0 && wait > 0) Thread.sleep(wait);
    String url = ENDPOINT + "?format=jsonv2&limit=2&addressdetails=1&countrycodes=kr&q="
        + URLEncoder.encode(query, StandardCharsets.UTF_8);
    var request = HttpRequest.newBuilder(URI.create(url))
        .timeout(Duration.ofSeconds(15))
        .header("User-Agent", "EcoCheckStudentProject/1.0 (offline Seoul public-bin dataset geocoding)")
        .header("Accept", "application/json")
        .GET().build();
    lastRequestAt = System.currentTimeMillis();
    var response = client.send(request, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
    if (response.statusCode() == 429 || response.statusCode() == 503)
      throw new IllegalStateException("Nominatim 요청 제한/일시 중단 응답: " + response.statusCode());
    if (response.statusCode() != 200)
      throw new IllegalStateException("Nominatim 응답 오류: " + response.statusCode());
    JsonArray results = JsonParser.parseString(response.body()).getAsJsonArray();
    if (results.size() == 0) return Optional.empty();
    var result = results.get(0).getAsJsonObject();
    var address = result.has("address") ? result.getAsJsonObject("address") : null;
    if (address == null || !address.has("borough")) return Optional.empty();
    String expectedDistrict = query.replaceFirst("^서울특별시\\s*", "").split("\\s+", 2)[0];
    if (!expectedDistrict.equals(address.get("borough").getAsString())) return Optional.empty();
    String expectedStreet = query.replaceFirst("^서울특별시\\s*[^\\s]+\\s*", "").split("\\s+")[0];
    String returnedStreet = address.has("road") ? address.get("road").getAsString() : "";
    if (!expectedStreet.isBlank() && !returnedStreet.contains(expectedStreet) && !expectedStreet.contains(returnedStreet))
      return Optional.empty();
    double lat = result.get("lat").getAsDouble(), lon = result.get("lon").getAsDouble();
    if (!Double.isFinite(lat) || !Double.isFinite(lon) || lat < 37 || lat > 38 || lon < 126 || lon > 128)
      return Optional.empty();
    return Optional.of(new double[] {lat, lon});
  }
}
