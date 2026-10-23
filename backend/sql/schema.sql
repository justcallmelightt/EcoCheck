-- MySQL Workbench에서 MySQL Server에 연결한 뒤 이 파일을 실행하세요.
-- 기존 테이블을 삭제하지 않습니다. CREATE DATABASE 권한이 있는 계정으로 실행합니다.
CREATE DATABASE IF NOT EXISTS ecocheck CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE ecocheck;

CREATE TABLE IF NOT EXISTS ecocheck_v2_scans (
    id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    owner_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    category_id VARCHAR(60) NOT NULL,
    name VARCHAR(100) NOT NULL,
    material VARCHAR(100) NOT NULL,
    model_version VARCHAR(100) NOT NULL,
    created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    INDEX idx_owner_created(owner_hash,created_at)
);

CREATE TABLE IF NOT EXISTS ecocheck_v2_bins (
    id VARCHAR(100) PRIMARY KEY,
    district VARCHAR(50) NOT NULL,
    address VARCHAR(500) NOT NULL,
    detail VARCHAR(1000) NOT NULL,
    location_type VARCHAR(200) NOT NULL,
    waste_type ENUM('general','recycling','unknown') NOT NULL,
    latitude DOUBLE NULL,
    longitude DOUBLE NULL,
    source_date CHAR(7) NOT NULL,
    source VARCHAR(200) NOT NULL,
    INDEX idx_location(latitude,longitude),
    CONSTRAINT chk_bin_coordinates CHECK ((latitude IS NULL AND longitude IS NULL) OR (latitude IS NOT NULL AND longitude IS NOT NULL AND latitude BETWEEN 37 AND 38 AND longitude BETWEEN 126 AND 128))
);

-- 앱 전용 계정은 아래 예시를 복사하고 비밀번호를 바꿔 별도로 실행하세요.
-- CREATE USER 'ecocheck'@'127.0.0.1' IDENTIFIED BY '본인이정한긴비밀번호';
-- GRANT SELECT, INSERT, UPDATE, DELETE ON ecocheck.* TO 'ecocheck'@'127.0.0.1';

SELECT 'tables ready' AS result;
