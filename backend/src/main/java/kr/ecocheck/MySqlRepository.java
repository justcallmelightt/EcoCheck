package kr.ecocheck;

import java.sql.*;
import java.util.*;
import kr.ecocheck.Models.*;

/** SQL 변경은 이 파일에 모읍니다. 기존 테이블과 충돌하지 않도록 v2 테이블을 사용합니다. */
final class MySqlRepository implements ScanRepository {
  private final AppConfig config;

  MySqlRepository(AppConfig c) {
    config = c;
  }

  Connection connect() throws SQLException {
    return DriverManager.getConnection(config.dbUrl(), config.dbUser(), config.dbPassword());
  }

  public boolean healthy() {
    try (var c = connect();
        var s = c.createStatement();
        var r = s.executeQuery("SELECT COUNT(*) FROM ecocheck_v2_scans")) {
      r.next();
      try (var b = s.executeQuery("SELECT COUNT(*) FROM ecocheck_v2_bins")) {
        return b.next();
      }
    } catch (SQLException e) {
      return false;
    }
  }

  public Scan save(String owner, Analysis a) throws SQLException {
    try (var c = connect()) {
      try (var s =
          c.prepareStatement(
              "INSERT INTO ecocheck_v2_scans(id,owner_hash,category_id,name,material,model_version)"
                  + " VALUES (?,?,?,?,?,?) ON DUPLICATE KEY UPDATE id=id")) {
        s.setString(1, a.id());
        s.setString(2, owner);
        s.setString(3, a.categoryId());
        s.setString(4, a.name());
        s.setString(5, a.material());
        s.setString(6, a.modelVersion());
        s.executeUpdate();
      }
      try (var s =
          c.prepareStatement("SELECT * FROM ecocheck_v2_scans WHERE id=? AND owner_hash=?")) {
        s.setString(1, a.id());
        s.setString(2, owner);
        try (var r = s.executeQuery()) {
          if (!r.next()) throw new SQLException("Conflicting analysis id");
          return scan(r);
        }
      }
    }
  }

  private Scan scan(ResultSet r) throws SQLException {
    return new Scan(
        r.getString("id"),
        r.getString("category_id"),
        r.getString("name"),
        r.getString("material"),
        r.getString("model_version"),
        r.getTimestamp("created_at", Calendar.getInstance(TimeZone.getTimeZone("UTC")))
            .toInstant()
            .toString());
  }

  public Page history(String owner, int limit, int offset) throws SQLException {
    try (var c = connect()) {
      long total;
      try (var s =
          c.prepareStatement("SELECT COUNT(*) FROM ecocheck_v2_scans WHERE owner_hash=?")) {
        s.setString(1, owner);
        try (var r = s.executeQuery()) {
          r.next();
          total = r.getLong(1);
        }
      }
      List<Scan> list = new ArrayList<>();
      try (var s =
          c.prepareStatement(
              "SELECT * FROM ecocheck_v2_scans WHERE owner_hash=? ORDER BY created_at DESC,id LIMIT"
                  + " ? OFFSET ?")) {
        s.setString(1, owner);
        s.setInt(2, limit);
        s.setInt(3, offset);
        try (var r = s.executeQuery()) {
          while (r.next()) list.add(scan(r));
        }
      }
      return new Page(list, total, limit, offset);
    }
  }

  public boolean delete(String owner, String id) throws SQLException {
    try (var c = connect();
        var s = c.prepareStatement("DELETE FROM ecocheck_v2_scans WHERE id=? AND owner_hash=?")) {
      s.setString(1, id);
      s.setString(2, owner);
      return s.executeUpdate() == 1;
    }
  }

  public List<Bin> bins(double lat, double lng, double radius, String wasteType)
      throws SQLException {
    double dLat = radius / 111_000, dLng = radius / (111_000 * Math.cos(Math.toRadians(lat)));
    String sql =
        "SELECT * FROM ecocheck_v2_bins WHERE latitude BETWEEN ? AND ? AND longitude BETWEEN ? AND"
            + " ?"
            + (wasteType.equals("all") ? "" : " AND waste_type=?");
    List<Bin> list = new ArrayList<>();
    try (var c = connect();
        var s = c.prepareStatement(sql)) {
      s.setDouble(1, lat - dLat);
      s.setDouble(2, lat + dLat);
      s.setDouble(3, lng - dLng);
      s.setDouble(4, lng + dLng);
      if (!wasteType.equals("all")) s.setString(5, wasteType);
      try (var r = s.executeQuery()) {
        while (r.next())
          list.add(
              new Bin(
                  r.getString("id"),
                  r.getString("district"),
                  r.getString("address"),
                  r.getString("detail"),
                  r.getString("location_type"),
                  r.getString("waste_type"),
                  r.getDouble("latitude"),
                  r.getDouble("longitude"),
                  r.getString("source_date")));
      }
    }
    return list;
  }

  void upsertBin(Bin b) throws SQLException {
    try (var c = connect();
        var s =
            c.prepareStatement(
                "INSERT INTO ecocheck_v2_bins VALUES (?,?,?,?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE"
                    + " district=VALUES(district),address=VALUES(address),detail=VALUES(detail),location_type=VALUES(location_type),waste_type=VALUES(waste_type),latitude=VALUES(latitude),longitude=VALUES(longitude),source_date=VALUES(source_date)")) {
      s.setString(1, b.id());
      s.setString(2, b.district());
      s.setString(3, b.address());
      s.setString(4, b.detail());
      s.setString(5, b.locationType());
      s.setString(6, b.wasteType());
      if (b.latitude() == null) s.setNull(7, Types.DOUBLE);
      else s.setDouble(7, b.latitude());
      if (b.longitude() == null) s.setNull(8, Types.DOUBLE);
      else s.setDouble(8, b.longitude());
      s.setString(9, b.sourceDate());
      s.setString(10, "서울열린데이터광장 OA-15069");
      s.executeUpdate();
    }
  }
}
