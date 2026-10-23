package kr.ecocheck;

import java.sql.SQLException;
import java.util.*;
import kr.ecocheck.Models.*;

interface ScanRepository {
  boolean healthy();

  Scan save(String owner, Analysis analysis) throws SQLException;

  Page history(String owner, int limit, int offset) throws SQLException;

  boolean delete(String owner, String id) throws SQLException;

  List<Bin> bins(double lat, double lng, double radius, String wasteType) throws SQLException;
}
