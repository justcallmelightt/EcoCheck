package kr.ecocheck;

import com.google.gson.Gson;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import kr.ecocheck.Models.Guide;

/** AI는 분류만 수행하고, 배출 절차는 수정 가능한 검토용 공통 JSON에서 가져옵니다. */
final class GuideService {
  private final List<Guide> guides;

  GuideService() throws IOException {
    try (var stream = getClass().getResourceAsStream("/recycling-guides.json")) {
      if (stream == null) throw new IOException("recycling-guides.json 없음");
      guides =
          List.of(
              new Gson()
                  .fromJson(new InputStreamReader(stream, StandardCharsets.UTF_8), Guide[].class));
    }
  }

  List<Guide> all() {
    return guides;
  }

  Optional<Guide> find(String id) {
    return guides.stream().filter(g -> g.id().equals(id)).findFirst();
  }
}
