-- MySQL Workbench의 mirim 연결에서 실행하세요. 조회만 수행합니다.

-- 전체 쓰레기통 수: 현재 6849
SELECT COUNT(*) AS total_bins FROM ecocheck.ecocheck_v2_bins;

-- 종류별 개수: general 4090, recycling 2275, unknown 484
SELECT waste_type,COUNT(*) AS count
FROM ecocheck.ecocheck_v2_bins GROUP BY waste_type;

-- 자치구별 개수
SELECT district,COUNT(*) AS count
FROM ecocheck.ecocheck_v2_bins GROUP BY district ORDER BY district;

-- 좌표 준비 상태
SELECT
 SUM(latitude IS NOT NULL AND longitude IS NOT NULL) AS located,
 SUM(latitude IS NULL OR longitude IS NULL) AS not_located
FROM ecocheck.ecocheck_v2_bins;

-- 주소/자치구 누락
SELECT id,district,address FROM ecocheck.ecocheck_v2_bins
WHERE district IS NULL OR TRIM(district)='' OR address IS NULL OR TRIM(address)='';

-- 종류 미확인 샘플: 실제 종류를 확인하기 전에는 임의 변경하지 않습니다.
SELECT id,district,address,detail,waste_type
FROM ecocheck.ecocheck_v2_bins WHERE waste_type='unknown' ORDER BY id LIMIT 20;

-- 분석 기록 수
SELECT COUNT(*) AS total_scans FROM ecocheck.ecocheck_v2_scans;
