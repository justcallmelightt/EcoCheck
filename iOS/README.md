# EcoCheck iOS

SwiftUI 홈 화면에 사진 촬영·앨범 선택, Java 서버의 Gemini 분석, 기본 안내, 서버 기록 저장·조회·삭제를 연결했습니다. 사진은 사용자가 결과 화면에서 전송을 선택했을 때만 서버를 거쳐 Google Gemini로 전송됩니다. 기록은 결과를 확인하고 저장 버튼을 눌렀을 때만 MySQL에 저장됩니다.

## 실행과 기능

Mac/Xcode 16 이상에서 `EcoCheck.xcodeproj`를 엽니다. iOS 17 이상을 대상으로 합니다. 실제 아이폰 실행에는 본인의 Signing Team이 필요합니다. 카메라는 실제 기기, 앨범은 시뮬레이터에서도 확인할 수 있습니다. Windows의 VS Code에서는 Swift 소스를 편집할 수 있고 빌드·실행은 Mac/Xcode가 필요합니다.

1. 스캔을 누르고 카메라나 앨범에서 사진을 가져옵니다.
2. 결과 화면에서 전송 안내를 읽고 동의하면 사진을 4MiB 이하 JPEG로 줄여 `/api/v1/analyze`에 보냅니다. 전송하지 않고 기본 안내를 볼 수도 있습니다.
3. 서버의 재질·분리배출 안내·판단 근거를 보여줍니다. 저장이 허용된 결과만 사용자가 확인한 뒤 `analysisId`로 `/api/v1/scans`에 저장합니다.
4. **기록**에서 조회·스와이프 삭제, **설정**에서 서버 주소를 지정합니다.

서버가 없거나 분석을 원하지 않을 때 **기본 분리배출 안내 보기**에서 수동으로 안내를 확인할 수 있습니다. 수동 선택은 AI 결과로 저장하지 않습니다. 지도 탭은 Apple MapKit 지도를 표시하고 `/api/v1/bins`에서 주변 쓰레기통을 가져옵니다. 주소를 좌표로 변환·적재해야 마커가 나타납니다. 홈의 CO₂·포인트·리사이클 0 표시는 기존 디자인이며 실측·적립 기능이나 기록 개수와 연결하지 않았습니다.

## 기존 Core ML 코드

`OnDeviceClassifier.swift`는 별도 실험용 코드로 남아 있지만 현재 스캔 화면에서는 호출하지 않습니다. 기기 내 모델 `WasteClassifier`가 없어도 서버에 Gemini 키가 설정돼 있으면 분석을 요청할 수 있습니다. 반대로 서버나 키가 없으면 AI 분석은 동작하지 않습니다.

향후 기기 내 분석을 선택 기능으로 되살리려면:

1. 수집·검토한 이미지로 **Core ML 이미지 분류 모델**을 학습하거나 변환하세요. 학습 데이터가 없는 상태이므로 이 저장소는 학습 완료 모델을 제공하지 않습니다. Teachable Machine의 `model.json`은 이 코드에 바로 넣을 수 없습니다.
2. 클래스 이름을 `shared/recycling-guides.json`의 ID와 일치시키세요. 현재는 `pet_bottle`, `aluminum_can`, `steel_can`, `glass_bottle`, `cardboard` 5개입니다. 계획한 15종으로 확장할 때 공통 JSON·학습 데이터·서버 테스트를 함께 수정하세요.
3. `WasteClassifier.mlmodel` 또는 `WasteClassifier.mlpackage`를 Xcode의 EcoCheck 그룹에 추가하고 **Target Membership: EcoCheck**를 선택하세요. 모델이 빌드 단계에서 컴파일되어 앱 번들의 `WasteClassifier.mlmodelc`로 포함되는지 확인합니다.
4. 모델 메타데이터 **Version**에 `1.0.0`처럼 영문·숫자로 시작하는 영문·숫자·`.`·`_`·`-` 80자 이내 값을 입력하세요. 버전이 없으면 분석을 중단합니다.
5. 입력은 이미지, 출력은 Vision의 `VNClassificationObservation`으로 해석할 수 있는 classifier여야 합니다. 전처리는 `.centerCrop`과 일치해야 합니다. 다른 전처리로 학습했다면 코드를 조정하세요.
6. 별도 테스트 사진으로 복잡한 배경·오염·여러 물체·지원하지 않는 물체를 검증하세요. 70% 기준은 초기값이며 정확도를 보증하지 않습니다. 모델의 일반 물체 라벨을 임의로 재질로 치환하지 마세요.

현재 서버 분석은 불확실한 결과의 저장을 막습니다. 저장 재시도에는 서버가 준 동일한 `analysisId`를 사용합니다. 기본 안내는 지역별 검토가 필요한 개발용 데이터입니다.

## 서버 연결

`backend/README.md`에 따라 Java와 MySQL을 실행한 뒤 앱 **설정**에 기본 서버 주소만 입력하세요. 경로·계정·DB 비밀번호는 넣지 않습니다.

- 실제 아이폰: 같은 Wi-Fi의 PC 주소(예: `http://192.168.x.x:8080`). 서버는 `ECOCHECK_HOST=0.0.0.0`으로 실행해야 합니다.
- 같은 Mac에서 서버와 시뮬레이터를 실행한다면 `http://127.0.0.1:8080`을 사용할 수 있습니다. Windows 서버는 그 PC의 IP를 사용합니다.
- Debug의 `Info-Debug.plist`에서만 개발용 HTTP를 허용합니다. 앱 URL 검증은 loopback·사설 IPv4만 받습니다. Release는 ATS 예외가 없고 HTTPS만 허용합니다.
- 256비트 난수 기기 토큰은 Keychain에 저장합니다. 로그인·기기 간 동기화는 아직 없습니다. 사진 분석과 기록 조회에는 서버가 필요하지만 기본 안내는 오프라인에서도 볼 수 있습니다.

## 지도와 쓰레기통 데이터

지도는 Apple MapKit을 사용하므로 별도 지도 SDK 키가 필요하지 않습니다. 앱은 현재 위치 또는 위치 권한이 없을 때 서울시청을 기준으로 `/api/v1/bins`에 주변 1km 쓰레기통을 조회합니다. 원본 6,849건에는 좌표가 없어 서버에서 주소 변환·좌표 적재를 마치기 전에는 빈 지도 마커가 정상입니다.

## 파일과 검증

- `ContentView.swift`, `CameraCapture.swift`: 홈과 사진 입력
- `OnDeviceClassifier.swift`: 현재 화면에서 호출하지 않는 기기 내 모델 실험 코드
- `ScanResultView.swift`: 사진 전송 선택·서버 분석 결과·수동 안내·저장
- `BinMapView.swift`: 현재 위치와 서울시 쓰레기통 조회·Apple MapKit 지도 마커
- `EcoCheckAPI.swift`: 서버 통신·Keychain 토큰
- `HistoryView.swift`: 기록 조회·삭제·서버 설정
- `shared/recycling-guides.json`(저장소 루트 기준): 앱 번들과 Java 서버가 함께 쓰는 안내 원본
- `EcoCheck/Fonts/LICENSE.txt`: Pretendard의 SIL Open Font License

Java 서버 검증 범위는 `backend/TEST-RESULTS.md`를 확인하세요. iOS와 실제 Gemini 서비스의 연결, 실제 사진 판별 정확도는 별도로 확인해야 합니다.

```sh
xcodebuild -project iOS/EcoCheck.xcodeproj -target EcoCheck -configuration Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
```
