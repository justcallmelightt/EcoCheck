CREATE TABLE IF NOT EXISTS waste_categories (
    id VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    material VARCHAR(100) NOT NULL,
    steps JSON NOT NULL,
    note TEXT NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS scan_records (
    owner_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    category_id VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    confidence DOUBLE NOT NULL,
    model_version VARCHAR(80) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (owner_hash, id),
    INDEX idx_scan_owner_time (owner_hash, created_at, id),
    CONSTRAINT fk_scan_category FOREIGN KEY (category_id) REFERENCES waste_categories(id),
    CONSTRAINT chk_scan_confidence CHECK (confidence >= 0.7 AND confidence <= 1)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
