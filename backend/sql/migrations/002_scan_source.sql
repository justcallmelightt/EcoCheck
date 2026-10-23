-- ecocheck_v2_scans에 AI/수동 기록 구분을 추가합니다. 기존 기록은 gemini로 취급합니다.
USE ecocheck;

SET @has_source = (
    SELECT COUNT(*)
    FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'ecocheck_v2_scans'
      AND COLUMN_NAME = 'source'
);
SET @source_migration = IF(
    @has_source = 0,
    'ALTER TABLE ecocheck_v2_scans ADD COLUMN source VARCHAR(20) NOT NULL DEFAULT ''gemini'' AFTER material',
    'SELECT 1'
);
PREPARE source_migration_stmt FROM @source_migration;
EXECUTE source_migration_stmt;
DEALLOCATE PREPARE source_migration_stmt;
