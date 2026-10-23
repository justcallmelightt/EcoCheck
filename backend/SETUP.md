# MySQL Workbench·API 키·쓰레기통 데이터 준비

## 1. Workbench

Workbench Home → MySQL Connections에서 실행 중인 MySQL Server의 host/port/user로 연결합니다. Workbench가 설치되어 있어도 Server가 중지되어 있으면 접속할 수 없습니다. 기본 예시는 127.0.0.1:3306입니다. 본인 연결 설정이 다르면 그 값을 사용하세요.

1. File → Open SQL Script → `sql/schema.sql` 선택.
2. 전체 SQL 실행(번개 버튼). `ecocheck_v2_scans`, `ecocheck_v2_bins`가 생겼는지 SCHEMAS 새로고침.
3. 파일 하단의 전용 계정 예시에서 비밀번호를 본인이 정한 값으로 바꾸고 주석을 해제해 별도로 실행합니다. 기존 계정이면 새 계정을 만들 필요는 없습니다.
4. `.env.example`을 `.env`로 복사하고 실제 DB URL/계정/비밀번호를 설정합니다.

테이블에는 사진·Gemini 키·네이버 Secret·기기 토큰 원문을 저장하지 않습니다. 기존 프로젝트의 테이블은 유지하며 v2 테이블로 새 기록을 시작합니다. 옛 기록을 옮기는 마이그레이션은 포함하지 않습니다.

확인 SQL:

```sql
USE ecocheck;
SELECT * FROM ecocheck_v2_scans ORDER BY created_at DESC LIMIT 20;
SELECT waste_type,COUNT(*) FROM ecocheck_v2_bins GROUP BY waste_type;
SELECT COUNT(*) AS located FROM ecocheck_v2_bins WHERE latitude IS NOT NULL;
```

## 2. Gemini 발급

[Google AI Studio](https://aistudio.google.com/apikey)에서 API 키를 만들고 `.env`의 GEMINI_API_KEY에 넣습니다. 모델은 GEMINI_MODEL에서 변경합니다. 기본 모델 gemini-3.8-flash는 2026-10-23 공식 모델 목록을 기준으로 지정했습니다. 계정별 모델 접근과 사용량은 발급 후 확인해야 합니다.

`gemini-3.8-flash`의 Standard API는 공식 요금표에 무료 티어가 표시돼 있습니다. 무료 티어는 요청·토큰 한도가 있으며 계정의 실제 한도는 AI Studio에서 확인합니다. 무료 티어에 전송한 내용은 Google 제품 개선에 사용될 수 있으므로 개인정보가 보이는 사진은 테스트에 사용하지 마세요. 서버는 무료 티어를 강제할 수 없으니 유료 프로젝트의 키를 연결하기 전에는 계정의 결제 상태를 확인하세요.

DB와 네이버 지도 설정에 앞서 Gemini 사진 호출만 확인하려면, 저장소 루트에서 `backend/.env.example`을 `backend/.env`로 복사해 키를 넣고 아래 명령을 실행하세요. 사진은 JPEG/PNG 4MiB 이하로 준비합니다. 이 명령은 실제 Gemini API 요청을 1회 보내지만 사진이나 키를 DB·출력 파일에 저장하지 않습니다.

```sh
cd backend
./mvnw package
java -jar target/ecocheck-server-0.1.0.jar --check-gemini-image /absolute/path/to/test-photo.jpg
```

`categoryId`, `needsConfirmation`, `reason`이 반환되면 사진 요청·응답 계약을 확인한 것입니다. AI 판단의 정확도나 iOS 앱 전체 흐름은 별도 사진과 실제 앱에서 검증해야 합니다. 키는 채팅, 커밋, 스크린샷에 노출하지 마세요.

## 3. 네이버 Maps 발급

[NAVER Cloud Maps](https://www.ncloud.com/product/application/maps) → 콘솔 → Maps → Application 등록.

- iOS 지도 표시: Mobile Dynamic Map 선택, 앱의 정확한 Bundle ID 등록.
- 서버 주소 변환: Geocoding 선택.
- 발급한 Client ID와 Secret을 `.env`에 각각 넣습니다.
- Client ID만 iOS 지도 SDK에서 사용하고 Secret은 서버에 보관합니다.

iOS 앱의 Bundle ID는 Xcode 타깃에 설정된 값과 정확히 같아야 합니다. `--check-naver`는 DB나 Gemini 없이 서울시청 주소를 한 번 변환해 서버 키와 Geocoding 활성화 여부를 확인합니다. 이 명령만으로 iOS 지도 표시까지 검증되지는 않습니다.

```sh
cd backend
./mvnw package
java -jar target/ecocheck-server-0.1.0.jar --check-naver
```

두 API의 약관·결제 설정·이용 한도는 본인 계정에서 확인합니다. 서버 실행만으로 외부 API는 호출되지 않습니다. 아래 확인 명령은 실제 API를 호출하며 계정 사용량을 소비할 수 있습니다.

```powershell
java -jar target/ecocheck-server-0.1.0.jar --check-apis
```

Gemini는 짧은 텍스트 생성, 네이버는 서울시청 주소 변환을 검사합니다. Gemini 사진 품질과 iOS 지도 렌더링은 이 명령으로 검증되지 않습니다. 키가 없으면 SKIPPED로 표시합니다.

## 4. 서울시 쓰레기통

[서울시 가로휴지통 설치정보 OA-15069](https://data.seoul.go.kr/dataList/OA-15069/F/1/datasetView.do)에서 원본을 내려받았습니다. 원본 기준월 2025-11, 사이트 파일 수정일 2026-04-06, 수집일 2026-10-23입니다. 공개 파일 형태이므로 이 파일을 이용하는 데 서울 Open API 인증키는 필요하지 않습니다.

`data/seoul-bins-202511.xlsx`는 원본, `.json`은 앱용 정규화본입니다. 6,849개(일반 4,090 / 재활용 2,275 / 미확인 484), 주소 누락 2개는 JSON의 skipped에 남겼습니다. 원본 열은 A 연번, B 자치구명, C 설치위치, D 세부위치, E 설치장소유형, F 수거쓰레기종류입니다. 원본에는 위경도가 없습니다.

다시 변환하려면 Python 3에서 실행합니다:

```powershell
python scripts/convert-seoul-data.py data/seoul-bins-202511.xlsx data/seoul-bins-new.json
```

네이버 키를 넣고 먼저 최대 10개 주소만 변환하세요. 새 출력 파일을 지정해야 합니다.

```powershell
java -jar target/ecocheck-server-0.1.0.jar --geocode-bins data/seoul-bins-202511.json data/seoul-bins-located-01.json 10 중구
```

마지막 자치구 인수는 선택 사항입니다. 중구를 지정하면 서울시청 근처 시연용 좌표부터 준비할 수 있습니다. 주소 중복은 한 번만 호출합니다. 전체 정규화본에는 서로 다른 주소 3,926개가 있으므로 전체 변환 전 API 한도·비용을 확인하세요. 복수 후보/검색 실패는 좌표를 임의 선택하지 않습니다. 주소 중심 좌표는 시설물 실제 위치와 다를 수 있으므로 상세 위치와 대조하세요.

계속 변환하려면 이전 출력 JSON을 입력으로 사용하고 새로운 출력명을 지정합니다. 이미 좌표가 있는 항목은 건너뜁니다. 현재 실행 내에서 주소를 캐시합니다.

결과를 검토한 뒤 DB로 적재합니다:

```powershell
java -jar target/ecocheck-server-0.1.0.jar --import-bins data/seoul-bins-located-01.json
```

원본 JSON을 먼저 적재해도 되지만 좌표가 없으므로 지도 검색에는 나오지 않습니다. 같은 ID 재적재는 해당 항목을 갱신하며, 파일에서 빠진 예전 항목을 삭제하지 않습니다. 과거 자료 정리는 별도 검토 후 수행해야 합니다.

## 5. 테스트

```powershell
.\mvnw.cmd test
```

일반 HTTP 테스트는 외부 키 없이 로컬 공급자 대역 서버로 실행합니다. MySQL 통합 테스트는 별도 DB 환경변수가 없으면 1개가 skipped됩니다.

MySQL 통합 검증은 전용 `ecocheck_test` DB를 만들어 schema.sql의 DB 이름을 바꿔 적용한 뒤 실행합니다. 실제 서비스 DB를 지정하지 마세요.

```powershell
$env:ECOCHECK_TEST_DB_URL='jdbc:mysql://127.0.0.1:3306/ecocheck_test?connectionTimeZone=UTC'
$env:ECOCHECK_TEST_DB_USER='테스트DB계정'
$env:ECOCHECK_TEST_DB_PASSWORD='테스트DB비밀번호'
.\mvnw.cmd test
```

## 공식 문서

- [Gemini REST generateContent](https://ai.google.dev/api/generate-content)
- [Gemini 모델 목록](https://ai.google.dev/gemini-api/docs/models)
- [Naver Maps iOS 시작](https://navermaps.github.io/ios-map-sdk/guide-en/1.html)
- [Naver Maps API 공통 주소](https://api.ncloud-docs.com/docs/application-maps-overview)
- [서울시 원본 데이터](https://data.seoul.go.kr/dataList/OA-15069/F/1/datasetView.do)
