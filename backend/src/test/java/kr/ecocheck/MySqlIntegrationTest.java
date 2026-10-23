package kr.ecocheck;

import static org.junit.jupiter.api.Assertions.*;

import java.sql.*;
import java.util.*;
import kr.ecocheck.Models.*;
import org.junit.jupiter.api.*;

/** 별도 테스트 DB만 지정하세요. schema.sql로 테이블을 먼저 만듭니다. */
class MySqlIntegrationTest {
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
