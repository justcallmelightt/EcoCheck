package kr.ecocheck;

import com.google.gson.Gson;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.List;
import kr.ecocheck.ScanDataModels.Guide;

final class RecyclingGuideLoader {
    private RecyclingGuideLoader() {}

    static List<Guide> load() throws IOException {
        var stream = RecyclingGuideLoader.class.getResourceAsStream("/recycling-guides.json");

        if (stream == null)
            throw new IOException("Missing recycling-guides.json");

        try (var reader = new InputStreamReader(stream, StandardCharsets.UTF_8)) {
            return List.copyOf(Arrays.asList(new Gson().fromJson(reader, Guide[].class)));
        }
    }
}
