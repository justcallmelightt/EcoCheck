# API 계약

기본 주소 `http://127.0.0.1:8080`. iPhone에서는 PC의 사설 IP를 사용합니다. Windows 방화벽은 개인 네트워크에 필요한 포트만 허용하고 앱 Debug 설정에서만 HTTP를 사용하세요. 공개 서비스는 HTTPS 프록시, 사용자 인증, 비용/요청량 제한을 추가해야 합니다. 현재 서버는 단일 프로세스 로컬 개발용입니다.

| 방식 | 경로 | 기능 |
|---|---|---|
| GET | /health | DB 테이블 접근 확인, 키 설정 여부. 외부 API 호출은 수행하지 않음 |
| GET | /api/v1/categories | 공통 분리배출 안내 5종 |
| GET | /api/v1/map-config | 지도 SDK의 공개 Client ID |
| GET | /api/v1/bins?lat=37.5665&lng=126.978&radius=1000&type=all | 주변 쓰레기통 최대 100개, 거리순 |
| POST | /api/v1/analyze | Gemini 사진 분석, DB 저장 없음 |
| POST | /api/v1/scans | 확인한 분석 결과 저장 |
| GET | /api/v1/scans?limit=50&offset=0 | 내 기록 조회 |
| DELETE | /api/v1/scans/{id} | 내 기록 삭제 |
| GET | /api/v1/statistics | 내 저장 기록 수 |

`analyze`, `scans`, `statistics`는 `Authorization: Bearer <64자리 소문자 16진수 토큰>`이 필요합니다. 앱에서 보안 난수 32바이트를 생성하고 Keychain에 보관합니다. 서버는 SHA-256 해시로 기록을 구분합니다. 토큰을 잃으면 기록을 복구할 수 없습니다. 회원 계정 시스템은 아닙니다.

## 사진 분석

사진 전송 전 앱에서 Gemini 전송을 사용자에게 알려주세요. 기존 기기 내부 AI와 달리 이미지가 Java 서버를 거쳐 Google로 전송됩니다. 서버 DB/파일에는 사진을 저장하지 않습니다. Google 측 데이터 처리 조건은 사용하는 요금제/계정의 약관을 확인하세요.

```json
{"mimeType":"image/jpeg","imageBase64":"순수 base64 값 (data:image 접두사 제외)"}
```

Content-Type은 application/json. JPEG/PNG 최대 4MiB, 최대 2500만 픽셀. iPhone HEIC는 JPEG로 변환·축소해서 보냅니다. 같은 토큰으로 분당 10회, 서버 전체 동시 분석 2개입니다. 서버 재시작 시 제한/분석 임시 결과는 초기화됩니다. 이 제한은 비용 보호의 보조 수단이며 공개 배포의 인증·IP 기반 제한을 대체하지 않습니다.

응답 형태 예시이며 실제 AI 판별 결과는 아닙니다:

```json
{
  "id":"서버가 생성한 UUID",
  "categoryId":"pet_bottle",
  "name":"투명 페트병",
  "material":"PET",
  "steps":["내용물을 비우고 물로 헹궈주세요."],
  "note":"지역별 배출 기준을 확인해주세요.",
  "reason":"AI가 반환한 판단 근거",
  "saveAllowed":true,
  "source":"gemini",
  "modelVersion":"gemini-3.8-flash"
}
```

신뢰도를 임의의 정확도 수치로 만들지 않습니다. 미지원/미확정 결과는 `saveAllowed=false`이며 기록 저장이 막힙니다. 재촬영 또는 `/categories`로 수동 안내를 보여주세요. 수동 선택을 AI 기록으로 저장하지 않습니다. AI 출력은 정답 보장이 아니며 실제 모델 정확도는 별도 사진 세트로 평가해야 합니다.

## 저장·조회·삭제

사용자가 결과를 확인한 뒤 다음을 보냅니다:

```json
{"analysisId":"위 분석 응답의 id","confirmed":true}
```

서버에 보관한 동일 기기의 분석 결과만 저장할 수 있습니다. 결과 유효시간 30분. 재시도는 같은 analysisId를 사용하며 DB에는 한 건만 저장됩니다. 분석 결과를 서버가 재시작 후에는 기억하지 못하므로 저장 실패 시 먼저 기록을 조회한 뒤 필요하면 다시 분석합니다. 기록을 삭제하면 임시 분석도 제거해 같은 결과로 되살릴 수 없게 합니다.

저장 응답은 `id,categoryId,name,material,modelVersion,createdAt`입니다. 생성 시각은 서버 UTC(ISO 8601)입니다. 조회는 `{items:[...],total:1,limit:50,offset:0}`. limit 1~100, offset 0~10000.

## 지도 데이터

type은 all/general/recycling/unknown. 반경은 100~5000m. 검색 좌표는 서울 주변 영역 위도 37~38, 경도 126~128을 허용합니다. 해당 범위 밖 검색은 400입니다. 마커 좌표는 `items[].bin.latitude/longitude`, 거리는 `items[].distanceMeters`입니다.

원본은 2025-11 기준 가로휴지통 자료입니다. 좌표가 없는 항목은 조회에서 제외됩니다. 키 미발급 상태에서는 좌표 변환을 하지 않았으므로 빈 결과가 정상입니다. 주소 중심점은 실제 쓰레기통 지점과 다를 수 있습니다. 지도에 출처·기준월·위치 오차 안내를 함께 표시하세요. 재활용으로 표시된 통이 모든 재활용품을 받는다는 의미는 아닙니다.

## 오류

`{"error":{"code":"GEMINI_NOT_CONFIGURED","message":"..."}}`

- 400: 입력/JSON/좌표 오류
- 401: 토큰 없음 또는 형식 오류
- 404: 없는 경로·다른 기기의 기록·만료 결과
- 405: 잘못된 HTTP 방식
- 413/415: 크기/Content-Type 오류
- 422: 불확실한 결과 저장 불가
- 429: 앱 자체 요청 제한
- 502/503/504: 외부 API 오류·키 미설정·DB 불가·타임아웃

외부 API 비밀키나 원문 오류 응답은 클라이언트로 반환하지 않습니다.

## 기존 iOS에서 바꿀 부분

1. `OnDeviceClassifier` 호출 대신 압축 JPEG를 `/analyze`에 전송합니다. 전송 전 사용자에게 알리고 취소할 수 있게 합니다.
2. ScanResult 모델에서 confidence 대신 reason/saveAllowed를 읽습니다. modelVersion은 유지합니다.
3. 저장 요청의 id/categoryId/confidence/modelVersion 4필드를 보내던 코드를 analysisId/confirmed로 변경합니다.
4. 기록 모델의 confidence는 제거합니다. 조회·삭제·통계 주소와 토큰 방식은 유지합니다.
5. 지도 화면에 Naver Maps iOS SDK를 설치하고 앱 Bundle ID를 네이버 콘솔에 등록합니다. Mobile Dynamic Map을 선택합니다.
6. 현재 위치는 iOS CoreLocation에서 사용자 권한을 받은 뒤 서버 쿼리에 넣습니다. 주변 목록을 지도의 마커로 표시합니다.

네이버 Secret과 Gemini 키는 앱에 넣지 않습니다. 네이버 지도 SDK 렌더링 성공 여부는 Mac/Xcode 및 실제 등록된 iOS 앱에서 별도 검증해야 합니다.
