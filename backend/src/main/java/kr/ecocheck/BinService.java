package kr.ecocheck;

import java.sql.SQLException;
import java.util.*;
import kr.ecocheck.Models.*;

final class BinService {
  private final ScanRepository db;

  BinService(ScanRepository db) {
    this.db = db;
  }

  List<NearbyBin> nearby(double lat, double lng, double radius, String type) throws SQLException {
    if (!Double.isFinite(lat)
        || !Double.isFinite(lng)
        || lat < 37
        || lat > 38
        || lng < 126
        || lng > 128
        || !Double.isFinite(radius)
        || radius < 100
        || radius > 5000
        || !Set.of("all", "general", "recycling", "unknown").contains(type))
      throw new ApiException(400, "INVALID_LOCATION", "서울 주변 좌표와 반경 100~5000m, 올바른 type을 입력해주세요.");
    return db.bins(lat, lng, radius, type).stream()
        .filter(b -> b.latitude() != null && b.longitude() != null)
        .map(b -> new NearbyBin(b, distance(lat, lng, b.latitude(), b.longitude())))
        .filter(b -> b.distanceMeters() <= radius)
        .sorted(Comparator.comparingDouble(NearbyBin::distanceMeters))
        .limit(100)
        .toList();
  }

  static double distance(double lat1, double lng1, double lat2, double lng2) {
    double a =
        Math.pow(Math.sin(Math.toRadians(lat2 - lat1) / 2), 2)
            + Math.cos(Math.toRadians(lat1))
                * Math.cos(Math.toRadians(lat2))
                * Math.pow(Math.sin(Math.toRadians(lng2 - lng1) / 2), 2);
    return 6_371_000 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(Math.max(0, 1 - a)));
  }
}
