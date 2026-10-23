# EcoCheck — AI 제외 프론트 연결 안내

2026-10-24 로컬 실행 검증 결과입니다. 기존 AI 코드는 삭제하지 않았으며, 아래 기능은 AI를 호출하지 않습니다.

## 완료한 확인

- MySQL 접속 정상. 쓰레기통 6,849건이 원본과 일치하며 누락·추가·필드 불일치 0건입니다.
- 좌표가 있는 데이터는 0건입니다. 주변 검색의 빈 배열은 현재 데이터 상태를 반영합니다.
- 읽기 전용 API 검사 9개 통과. 분리배출 안내 5개 모두 ID·이름·단계가 있는지 추가 확인했습니다.
- 네이버 인증 설정은 없는 상태입니다. 주소 변환을 호출하거나 임의의 좌표를 DB에 넣지 않았습니다.

## 프론트에서 지금 연결할 기능

서버 기본 주소: PC에서 `http://127.0.0.1:8080`. 이 두 API에는 로그인/기기 토큰이 필요 없습니다.

### 분리배출 안내

`GET /api/v1/categories`

응답은 배열입니다. `id`, `name`, `material`, `steps`, `note`를 사용하세요. 선택한 항목의 안내를 표시하면 됩니다. 개별 항목 조회 API는 없으므로 받은 배열에서 ID로 선택합니다.

실제 응답: `categories-response.json`.

### 주변 쓰레기통

`GET /api/v1/bins?lat=37.5665&lng=126.978&radius=1000&type=all`

`items[].bin.latitude`, `items[].bin.longitude`로 마커를 만들고 `items[].distanceMeters`로 거리를 표시하세요. 반경은 100~5000m, 종류는 all/general/recycling/unknown, 거리순 최대 100건입니다. 실제 응답: `bins-response.json`.

지금은 좌표가 없어 `items=[]`, `count=0`입니다. 화면에서는 조회 결과 없음으로 처리하고, 지도 준비 완료로 판단하지 마세요.

AI 사진 분석과 분석 기록 저장은 현재 화면에 연결하지 않습니다. 직접 재질을 선택한 결과를 `/api/v1/scans`에 보내면 저장되지 않습니다. 수동 기록 저장은 별도 미구현 기능입니다.

## 남은 선행 조건: 좌표 변환

`addresses-to-geocode.json`은 동일 자치구·주소를 묶은 작업 목록입니다. 각 주소에 연결된 binIds가 있으나 좌표는 비워두었습니다. 인증키나 개인정보는 포함하지 않았습니다.

친구가 네이버 Geocoding 사용 설정이 된 키를 backend/.env에 준비하면, 프로젝트 루트의 PowerShell에서 먼저 확인합니다. 지도 SDK만 활성화한 키로 Geocoding까지 가능하다고 가정하지 마세요.

```powershell
java -jar .\backend\target\ecocheck-server-0.1.0.jar --check-naver
java -jar .\backend\target\ecocheck-server-0.1.0.jar --geocode-bins .\backend\data\seoul-bins-202511.json .\backend\data\seoul-bins-geocoded-review.json 10
```

최대 10회 주소 조회부터 확인합니다. 실제 호출에는 서비스 요금/할당량이 적용될 수 있습니다. 좌표는 주소 기준이며 시설물 상세 위치와 다를 수 있으므로 결과를 검토한 다음 반영합니다.

```powershell
java -jar .\backend\target\ecocheck-server-0.1.0.jar --import-bins .\backend\data\seoul-bins-geocoded-review.json
```

출력 파일이 이미 있으면 새 파일명을 사용하세요. 이 예시는 첫 10회 검토용이며 전체 좌표 적재가 완료된 상태는 아닙니다.

## 실행 및 재확인

프로젝트 루트에서:

```powershell
powershell -ExecutionPolicy Bypass -File .\backend\scripts\start-server.ps1
```

별도 터미널에서:

```powershell
powershell -ExecutionPolicy Bypass -File .\backend\scripts\check-local.ps1
```

휴대폰은 PC와 같은 Wi-Fi에서 PC의 사설 IP로 접속해야 합니다. 필요할 때 start-server.ps1에 `-Lan`을 지정하고 Windows의 개인 네트워크 방화벽 허용을 확인하세요. 이번 점검에서는 외부 접속 서버나 방화벽 규칙을 추가하지 않았습니다.

서버를 켜는 작업과 실제 휴대폰에서 지도를 확인하는 작업은 별도입니다. 실제 휴대폰 검증 및 좌표 반영 후 마커 검증은 아직 남아 있습니다.
