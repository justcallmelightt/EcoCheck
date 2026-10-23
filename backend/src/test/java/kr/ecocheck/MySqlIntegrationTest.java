package kr.ecocheck;

import static org.junit.jupiter.api.Assertions.*;

import java.sql.*;
import java.util.*;
import kr.ecocheck.Models.*;
import org.junit.jupiter.api.*;

/** 별도 테스트 DB만 지정하세요. schema.sql로 테이블을 먼저 만듭니다. */
class MySqlIntegrationTest {
  @Test
  void binImportUpdateAndNearbyFiltering() throws Exception {
    String url = System.getenv("ECOCHECK_TEST_DB_URL");
    Assumptions.assumeTrue(url != null && !url.isBlank(), "별도 MySQL 테스트 DB 미설정");
    if (!url.matches("jdbc:mysql://[^/]+/ecocheck_test(?:\\?.*)?"))
      throw new IllegalArgumentException("테스트 DB 이름은 ecocheck_test여야 합니다.");
    var config = new AppConfig("127.0.0.1", 0, url,
        System.getenv("ECOCHECK_TEST_DB_USER"), System.getenv("ECOCHECK_TEST_DB_PASSWORD"),
        "", "test", "", "");
    var db = new MySqlRepository(config);
    String prefix = "fixture-" + UUID.randomUUID() + "-";
    String[] ids = {prefix + "general", prefix + "recycling", prefix + "far", prefix + "unlocated"};
    try {
      db.upsertBin(new Bin(ids[0], "중구", "테스트 주소", "첫 위치", "테스트", "general", 37.5665, 126.978, "2025-11"));
      db.upsertBin(new Bin(ids[0], "중구", "수정된 주소", "둘째 위치", "테스트", "general", 37.5665, 126.978, "2025-11"));
      db.upsertBin(new Bin(ids[1], "중구", "테스트 주소", "", "테스트", "recycling", 37.567, 126.978, "2025-11"));
      db.upsertBin(new Bin(ids[2], "테스트구", "먼 주소", "", "테스트", "general", 37.9, 127.5, "2025-11"));
      db.upsertBin(new Bin(ids[3], "중구", "좌표 없는 주소", "", "테스트", "unknown", null, null, "2025-11"));
      var bins = new BinService(new MySqlRepository(config));
      var all = bins.nearby(37.5665, 126.978, 1000, "all").stream()
          .filter(item -> item.bin().id().startsWith(prefix)).toList();
      assertEquals(2, all.size());
      assertEquals(ids[0], all.get(0).bin().id());
      assertEquals("수정된 주소", all.get(0).bin().address());
      assertEquals(0, all.get(0).distanceMeters(), 0.01);
      var recycling = bins.nearby(37.5665, 126.978, 1000, "recycling").stream()
          .filter(item -> item.bin().id().startsWith(prefix)).toList();
      assertEquals(1, recycling.size());
      assertEquals(ids[1], recycling.get(0).bin().id());
    } finally {
      try (var connection = db.connect();
           var statement = connection.prepareStatement("DELETE FROM ecocheck_v2_bins WHERE id=?")) {
        for (String id : ids) { statement.setString(1, id); statement.executeUpdate(); }
      }
    }
  }

  @Test
  void persistsIsolatesAndDeletes() throws Exception {
    String url = System.getenv("ECOCHECK_TEST_DB_URL");
    Assumptions.assumeTrue(url != null && !url.isBlank(), "별도 MySQL 테스트 DB 미설정");
    if (!url.matches("jdbc:mysql://[^/]+/ecocheck_test(?:\\?.*)?"))
      throw new IllegalArgumentException("테스트 DB 이름은 ecocheck_test여야 합니다.");
    var config =
        new AppConfig(
            "127.0.0.1",
            0,
            url,
            System.getenv("ECOCHECK_TEST_DB_USER"),
            System.getenv("ECOCHECK_TEST_DB_PASSWORD"),
            "",
            "test",
            "",
            "");
    var db = new MySqlRepository(config);
    assertTrue(db.healthy(), "테스트 DB에 schema.sql을 적용하세요.");
    String owner = UUID.randomUUID().toString(), id = UUID.randomUUID().toString();
    var a =
        new Analysis(id, "pet_bottle", "투명 페트병", "PET", List.of(), "", "", true, "gemini", "test");
    try {
      db.save(owner, a);
      db.save(owner, a);
      assertEquals(1, new MySqlRepository(config).history(owner, 50, 0).total());
      assertEquals(0, db.history("other-" + owner, 50, 0).total());
      assertFalse(db.delete("other-" + owner, id));
      assertTrue(db.delete(owner, id));
      assertEquals(0, db.history(owner, 50, 0).total());
    } finally {
      db.delete(owner, id);
    }
  }
}
