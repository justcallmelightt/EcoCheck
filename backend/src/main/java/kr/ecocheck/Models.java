package kr.ecocheck;

import java.util.List;

final class Models {
  private Models() {}

  record Guide(String id, String name, String material, List<String> steps, String note) {}

  record Prediction(String categoryId, boolean needsConfirmation, String reason) {}


  record Analysis(
      String id,
      String categoryId,
      String name,
      String material,
      List<String> steps,
      String note,
      String reason,
      boolean saveAllowed,
      String source,
      String modelVersion) {}

  record Scan(
      String id,
      String categoryId,
      String name,
      String material,
      String modelVersion,
      String createdAt) {}

  record Page(List<Scan> items, long total, int limit, int offset) {}

  record Bin(
      String id,
      String district,
      String address,
      String detail,
      String locationType,
      String wasteType,
      Double latitude,
      Double longitude,
      String sourceDate) {}

  record NearbyBin(Bin bin, double distanceMeters) {}
}
