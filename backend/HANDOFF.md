# EcoCheck 친구에게 전달할 API 연결 안내

2026-10-24 기준. 실제 확인한 Java 서버의 현재 계약입니다. API 키·DB 비밀번호는 이 문서에 포함하지 않습니다.

GitHub 최신 main에는 iOS의 분석·지도 API 연결 코드가 추가되어 있습니다. 아래 연결 항목은 팀 작업 확인용이며, 실제 기기에서 연결이 성공했다고 검증한 결과는 아닙니다.

## 현재 담당 범위

- Java/MySQL: 분석 결과 보관·기록 저장/조회/삭제, 분리배출 안내, 주변 쓰레기통 조회.
- 친구: Gemini 연동과 프론트 화면, 네이버 지도 SDK 및 지도 키 준비.
- Google 로그인: 친구가 Supabase로 담당. 별도 이메일 회원가입/비밀번호 로그인은 만들지 않습니다.
- 실제 Gemini 서비스 사용은 운영자 및 앱 대상 사용자의 이용 조건을 충족하는지 먼저 확인해야 합니다. 이 문서의 계약 테스트는 로컬 대역 서버로만 수행했습니다.

## 먼저 맞출 두 가지

### 1. Gemini 결과가 어디에서 만들어지는가

현재 `POST /api/v1/scans`는 이 Java 서버가 `/api/v1/analyze`에서 발급한 분석 ID만 받습니다. 친구가 다른 서버에서 Gemini를 호출하고 결과나 임의 UUID를 보내면 저장되지 않습니다.

연결 방법은 아래 중 하나를 팀에서 확정해야 합니다.

- 기존 방식: Java의 GeminiClient와 분석 흐름에 연동하여 현재 API 계약 유지.
- 별도 서비스 방식: Java가 신뢰하는 분석 서비스에서 결과를 받아 검증·등록하는 기능을 추가. 현재 이 등록 API는 없습니다. 프론트가 전달한 결과를 검증 없이 저장하는 방식으로 바꾸지 않습니다.

### 2. 기록의 주인은 누구인가

현재는 기기 토큰별 기록입니다. 다른 기기에서 같은 Google 계정으로 로그인해도 기록이 자동으로 공유되지 않습니다.

Supabase 사용자별 기록으로 바꾸려면 Java가 Supabase access token의 서명·발급자·대상·만료 등을 검증한 뒤 `sub` 사용자 ID와 기록을 연결해야 합니다. 현재 64자리 기기 토큰 자리에 Supabase JWT를 그대로 넣으면 401입니다. 프론트가 보낸 Google 사용자 ID 문자열만으로 인증하지 않습니다.

**결정 대기:** 기기별 기록을 유지할지, 로그인 사용자별 기록으로 변경할지. 사용자별 저장이 필요하면 별도 작업 범위로 확정합니다.

## 개발 서버 접속

Java: `EcoCheckServerApplication.main` 실행. 로컬 PC에서는 `http://127.0.0.1:8080`.

실제 휴대폰에서는 PC의 사설 IP가 필요합니다. 같은 Wi-Fi에서 서버의 ECOCHECK_HOST 설정과 방화벽 개인 네트워크 허용을 확인합니다. 휴대폰에서 127.0.0.1은 PC가 아닙니다. 운영 배포에는 HTTPS와 적절한 인증·사용량 제한이 필요합니다.

### 공통 헤더

기록·분석 API:

```http
Authorization: Bearer <기기에서 보안 난수로 생성한 64자리 소문자 16진수>
Content-Type: application/json
```

기기 토큰은 Keychain에 보관합니다. 예시용 토큰을 실제 사용자 모두에게 공통으로 사용하지 않습니다. Gemini 키와 Naver Secret은 앱에 넣지 않습니다.

## 화면별 API

| 화면 | 요청 | 응답에서 사용할 값 |
|---|---|---|
| 수동 재질 선택/안내 | GET /api/v1/categories | id, name, material, steps, note |
| 사진 분석 | POST /api/v1/analyze | id, categoryId, name, material, steps, note, reason, saveAllowed, source, modelVersion |
| 결과 저장 | POST /api/v1/scans | 저장된 id, categoryId, name, material, modelVersion, createdAt |
| 기록 목록 | GET /api/v1/scans?limit=50&offset=0 | items, total, limit, offset |
| 기록 삭제 | DELETE /api/v1/scans/{id} | deleted |
| 기록 수 | GET /api/v1/statistics | totalScans |
| 주변 지도 | GET /api/v1/bins?lat=37.5665&lng=126.978&radius=1000&type=all | items[].bin, items[].distanceMeters |
| 서버 확인 | GET /health | database, status. 외부 API의 성공 보장은 아님 |

### 사진 분석 입력

```json
{"mimeType":"image/jpeg","imageBase64":"순수 base64 사진 값"}
```

JPEG/PNG 최대 4MiB·2500만 픽셀. HEIC는 앱에서 변환합니다. Gemini를 쓰는 경우 사진의 외부 전송을 사용자에게 안내해야 합니다.

### 기록 저장 입력

```json
{"analysisId":"분석 응답의 id","confirmed":true}
```

- 분석 응답의 필드 이름은 `id`, 저장 요청에서는 `analysisId`입니다.
- 같은 기기의 결과만 저장할 수 있으며 임시 결과는 30분 뒤 또는 서버 재시작 시 만료됩니다.
- saveAllowed=false인 결과는 저장할 수 없습니다. 동일 ID로 재요청하면 중복 저장하지 않습니다.
- 수동 재질 선택은 안내만 지원합니다. 수동 기록 저장 API는 아직 없습니다.
- 날짜는 UTC ISO 8601이며 화면에서 현지 시간으로 표시합니다.
- 기록 수는 분리배출 완료 횟수나 탄소 절감량이 아닙니다.

### 지도 응답 해석

`items[].bin`에는 id, district, address, detail, locationType, wasteType, latitude, longitude, sourceDate가 있습니다.

- wasteType: general / recycling / unknown.
- 검색 type: all / general / recycling / unknown.
- 반경: 100~5000m. 결과는 거리순 최대 100개.
- 현재 데이터는 6,849개지만 좌표가 없어서 주변 조회는 빈 배열이 정상입니다.
- 네이버 키 준비 후 주소를 좌표로 변환하고 DB에 반영해야 마커가 나옵니다.
- 주소 중심점과 실제 시설물 위치는 다를 수 있습니다. 상세 위치 및 출처·기준월도 보여주세요.
- 재활용 통 표시가 모든 재활용품을 받는다는 뜻은 아닙니다.

## 오류 화면

오류 형태: `{"error":{"code":"...","message":"..."}}`

- 400: 입력값 수정 안내.
- 401: 현재 지원하는 인증 토큰 확인.
- 404: 기록 없음 또는 분석 만료. 만료 결과를 저장하려면 다시 분석.
- 422: 불확실한 결과. 재촬영/수동 안내로 이동.
- GEMINI_UNAVAILABLE(503): 제한된 재시도 후에도 외부 서비스 불가. 재시도 버튼/수동 안내 제공.
- 504: 응답 시간 초과. 성공 결과로 표시하지 않음.

## 함께 확인할 순서

1. 분리배출 목록과 안내 화면 연결.
2. 기록 소유 기준 및 Gemini 결과 연결 경로 확정.
3. 이용 조건에 맞는 실제 분석 성공 후 결과 저장·조회·삭제 연결.
4. 네이버 좌표 변환을 작은 범위로 검증한 뒤 주변 검색·마커 연결.
5. 빈 목록·오류·재시도·실제 휴대폰 접속 확인.

현재 검증에는 실제 Gemini 성공, 네이버 지도 렌더링, Supabase 사용자 인증이 포함되지 않습니다.
