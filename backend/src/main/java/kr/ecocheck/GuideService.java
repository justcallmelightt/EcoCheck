package kr.ecocheck;

import com.google.gson.Gson;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import kr.ecocheck.Models.Analysis;
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

  Analysis manualSelection(String id, String categoryId) {
    Guide guide = find(categoryId)
        .orElseThrow(() -> new ApiException(400, "UNKNOWN_CATEGORY", "목록에 있는 분류를 선택해주세요."));
    return new Analysis(
        id,
        guide.id(),
        guide.name(),
        guide.material(),
        guide.steps(),
        guide.note(),
        "사용자가 분류를 직접 선택했습니다.",
        true,
        "manual",
        "manual-v1");
  }
}
