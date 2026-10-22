package kr.ecocheck;

import java.sql.SQLException;
import java.util.List;
import kr.ecocheck.Models.*;

interface Store {
    boolean healthy();
    List<Guide> guides() throws SQLException;
    SaveResult save(String ownerHash, ScanInput input) throws SQLException;
    ScanPage scans(String ownerHash, int limit, int offset) throws SQLException;
    Statistics statistics(String ownerHash) throws SQLException;
    boolean delete(String ownerHash, String id) throws SQLException;
}
