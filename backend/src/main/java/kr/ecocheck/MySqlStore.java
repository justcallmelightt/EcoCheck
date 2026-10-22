package kr.ecocheck;

import com.google.gson.Gson;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.sql.*;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import kr.ecocheck.Models.*;

final class MySqlStore implements Store {
    private final Config config;
    private final Gson json = new Gson();
    MySqlStore(Config config) { this.config = config; }

    private Connection connection() throws SQLException {
        return DriverManager.getConnection(config.dbUrl(), config.dbUser(), config.dbPassword());
    }

    void initialize() throws SQLException, IOException {
        try (var stream = getClass().getResourceAsStream("/schema.sql")) {
            if (stream == null) throw new IOException("Missing schema.sql");
            String schema = new String(stream.readAllBytes(), StandardCharsets.UTF_8);
            try (var c = connection(); var statement = c.createStatement()) {
                for (String sql : schema.split(";")) if (!sql.isBlank()) statement.execute(sql);
                try (var insert = c.prepareStatement("INSERT INTO waste_categories (id,name,material,steps,note) VALUES (?,?,?,?,?) "
                        + "ON DUPLICATE KEY UPDATE name=?,material=?,steps=?,note=?")) {
                    for (Guide guide : Catalog.load()) {
                        insert.setString(1, guide.id()); insert.setString(2, guide.name());
                        insert.setString(3, guide.material()); insert.setString(4, json.toJson(guide.steps()));
                        insert.setString(5, guide.note()); insert.setString(6, guide.name());
                        insert.setString(7, guide.material()); insert.setString(8, json.toJson(guide.steps()));
                        insert.setString(9, guide.note()); insert.addBatch();
                    }
                    insert.executeBatch();
                }
            }
        }
    }

    public boolean healthy() {
        try (var c = connection()) { return c.isValid(2); }
        catch (SQLException e) { return false; }
    }

    public List<Guide> guides() throws SQLException {
        try (var c = connection(); var s = c.prepareStatement("SELECT * FROM waste_categories ORDER BY id"); var r = s.executeQuery()) {
            List<Guide> result = new ArrayList<>();
            while (r.next()) result.add(new Guide(r.getString("id"), r.getString("name"), r.getString("material"),
                    Arrays.asList(json.fromJson(r.getString("steps"), String[].class)), r.getString("note")));
            return result;
        }
    }

    public SaveResult save(String ownerHash, ScanInput input) throws SQLException {
        try (var c = connection()) {
            boolean created = true;
            try (var s = c.prepareStatement("INSERT INTO scan_records (owner_hash,id,category_id,confidence,model_version) VALUES (?,?,?,?,?)")) {
                s.setString(1, ownerHash); s.setString(2, input.id()); s.setString(3, input.categoryId());
                s.setDouble(4, input.confidence()); s.setString(5, input.modelVersion()); s.executeUpdate();
            } catch (SQLException e) {
                if (e.getErrorCode() != 1062) throw e;
                created = false;
            }
            try (var s = c.prepareStatement(SELECT_SCAN + " WHERE s.owner_hash=? AND s.id=?")) {
                s.setString(1, ownerHash); s.setString(2, input.id());
                try (var r = s.executeQuery()) {
                    if (!r.next()) throw new SQLException("Saved record disappeared");
                    Scan scan = readScan(r);
                    if (!scan.categoryId().equals(input.categoryId()) || Double.compare(scan.confidence(), input.confidence()) != 0
                            || !scan.modelVersion().equals(input.modelVersion())) {
                        throw new ApiException(409, "SCAN_CONFLICT", "같은 기록 ID에 다른 결과를 저장할 수 없습니다.");
                    }
                    return new SaveResult(scan, created);
                }
            }
        }
    }

    private static final String SELECT_SCAN = "SELECT s.id,s.category_id,c.name,c.material,s.confidence,s.model_version,s.created_at "
            + "FROM scan_records s JOIN waste_categories c ON c.id=s.category_id";

    private Scan readScan(ResultSet r) throws SQLException {
        return new Scan(r.getString("id"), r.getString("category_id"), r.getString("name"), r.getString("material"),
                r.getDouble("confidence"), r.getString("model_version"), r.getTimestamp("created_at").toInstant().toString());
    }

    public ScanPage scans(String ownerHash, int limit, int offset) throws SQLException {
        try (var c = connection()) {
            // A single snapshot keeps the page and count consistent during concurrent saves.
            c.setAutoCommit(false);
            try (var s = c.prepareStatement(SELECT_SCAN + " WHERE s.owner_hash=? ORDER BY s.created_at DESC,s.id DESC LIMIT ? OFFSET ?")) {
                s.setString(1, ownerHash); s.setInt(2, limit); s.setInt(3, offset);
                List<Scan> items = new ArrayList<>();
                try (var r = s.executeQuery()) { while (r.next()) items.add(readScan(r)); }
                long total = count(c, ownerHash);
                c.commit();
                return new ScanPage(items, total, limit, offset);
            }
        }
    }

    private long count(Connection c, String ownerHash) throws SQLException {
        try (var s = c.prepareStatement("SELECT COUNT(*) FROM scan_records WHERE owner_hash=?")) {
            s.setString(1, ownerHash);
            try (var r = s.executeQuery()) { r.next(); return r.getLong(1); }
        }
    }

    public Statistics statistics(String ownerHash) throws SQLException {
        try (var c = connection()) { return new Statistics(count(c, ownerHash)); }
    }

    public boolean delete(String ownerHash, String id) throws SQLException {
        try (var c = connection(); var s = c.prepareStatement("DELETE FROM scan_records WHERE owner_hash=? AND id=?")) {
            s.setString(1, ownerHash); s.setString(2, id); return s.executeUpdate() == 1;
        }
    }
}
