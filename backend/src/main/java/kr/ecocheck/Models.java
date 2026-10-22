package kr.ecocheck;

import java.util.List;

final class Models {
    private Models() {}
    record Guide(String id, String name, String material, List<String> steps, String note) {}
    record ScanInput(String id, String categoryId, double confidence, String modelVersion) {}
    record Scan(String id, String categoryId, String name, String material, double confidence, String modelVersion, String createdAt) {}
    record SaveResult(Scan scan, boolean created) {}
    record ScanPage(List<Scan> items, long total, int limit, int offset) {}
    record Statistics(long totalScans) {}
}
