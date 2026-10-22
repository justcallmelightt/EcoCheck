# EcoCheck iOS

SwiftUI 홈 화면에 사진 촬영·앨범 선택, 기기 내 AI 분석 연결, 기본 안내, 서버 기록 저장·조회·삭제를 연결했습니다. **학습한 AI 모델은 아직 없습니다.** 모델이 없으면 준비되지 않았다고 안내하며 임의의 판별 결과를 만들거나 저장하지 않습니다.

## 실행과 기능

Mac/Xcode 16 이상에서 `EcoCheck.xcodeproj`를 엽니다. iOS 17 이상을 대상으로 합니다. 실제 아이폰 실행에는 본인의 Signing Team이 필요합니다. 카메라는 실제 기기, 앨범은 시뮬레이터에서도 확인할 수 있습니다. Windows의 VS Code에서는 Swift 소스를 편집할 수 있고 빌드·실행은 Mac/Xcode가 필요합니다.

1. 스캔을 누르고 카메라나 앨범에서 사진을 가져옵니다.
2. 별도 actor에서 Vision/Core ML로 분석합니다. 지원 라벨이고 신뢰도가 70% 이상이면 로컬 안내를 표시합니다.
3. **기록 저장**을 누를 때만 분류·신뢰도·모델 버전·UUID를 서버로 전송합니다. 사진은 전송하지 않습니다.
4. **기록**에서 조회·스와이프 삭제, **설정**에서 서버 주소를 지정합니다.

모델이 없으면 결과 화면의 **기본 분리배출 안내 보기**에서 수동으로 안내를 확인할 수 있습니다. 수동 선택은 AI 결과로 저장하지 않습니다. 지도는 미연결이고 홈의 CO₂·포인트·리사이클 0 표시는 기존 디자인입니다. 실측·적립 기능이나 기록 개수와 연결하지 않았습니다.

## 학습 모델 넣기

1. 수집·검토한 이미지로 **Core ML 이미지 분류 모델**을 학습하거나 변환하세요. 학습 데이터가 없는 상태이므로 이 저장소는 학습 완료 모델을 제공하지 않습니다. Teachable Machine의 `model.json`은 이 코드에 바로 넣을 수 없습니다.
2. 클래스 이름을 `shared/recycling-guides.json`의 ID와 일치시키세요. 현재는 `pet_bottle`, `aluminum_can`, `steel_can`, `glass_bottle`, `cardboard` 5개입니다. 계획한 15종으로 확장할 때 공통 JSON·학습 데이터·서버 테스트를 함께 수정하세요.
3. `WasteClassifier.mlmodel` 또는 `WasteClassifier.mlpackage`를 Xcode의 EcoCheck 그룹에 추가하고 **Target Membership: EcoCheck**를 선택하세요. 모델이 빌드 단계에서 컴파일되어 앱 번들의 `WasteClassifier.mlmodelc`로 포함되는지 확인합니다.
4. 모델 메타데이터 **Version**에 `1.0.0`처럼 영문·숫자로 시작하는 영문·숫자·`.`·`_`·`-` 80자 이내 값을 입력하세요. 버전이 없으면 분석을 중단합니다.
5. 입력은 이미지, 출력은 Vision의 `VNClassificationObservation`으로 해석할 수 있는 classifier여야 합니다. 전처리는 `.centerCrop`과 일치해야 합니다. 다른 전처리로 학습했다면 코드를 조정하세요.
6. 별도 테스트 사진으로 복잡한 배경·오염·여러 물체·지원하지 않는 물체를 검증하세요. 70% 기준은 초기값이며 정확도를 보증하지 않습니다. 모델의 일반 물체 라벨을 임의로 재질로 치환하지 마세요.

미지원 라벨·낮은 신뢰도에는 재촬영을 안내하고 저장을 막습니다. 사진마다 UUID를 만들고 저장 재시도에는 동일한 UUID를 사용합니다. 기본 안내는 지역별 검토가 필요한 개발용 데이터입니다.

## 서버 연결

`backend/README.md`에 따라 Java와 MySQL을 실행한 뒤 앱 **설정**에 기본 서버 주소만 입력하세요. 경로·계정·DB 비밀번호는 넣지 않습니다.

- 실제 아이폰: 같은 Wi-Fi의 PC 주소(예: `http://192.168.x.x:8080`). 서버는 `ECOCHECK_HOST=0.0.0.0`으로 실행해야 합니다.
- 같은 Mac에서 서버와 시뮬레이터를 실행한다면 `http://127.0.0.1:8080`을 사용할 수 있습니다. Windows 서버는 그 PC의 IP를 사용합니다.
- Debug의 `Info-Debug.plist`에서만 개발용 HTTP를 허용합니다. 앱 URL 검증은 loopback·사설 IPv4만 받습니다. Release는 ATS 예외가 없고 HTTPS만 허용합니다.
- 256비트 난수 기기 토큰은 Keychain에 저장합니다. 로그인·기기 간 동기화는 아직 없습니다. 기록 조회에는 서버가 필요하지만 로컬 AI·기본 안내에는 필요하지 않습니다.

## 파일과 검증

- `ContentView.swift`, `CameraCapture.swift`: 홈과 사진 입력
- `OnDeviceClassifier.swift`: 로컬 모델 실행·안내 매핑
- `ScanResultView.swift`: 결과·수동 안내·저장
- `EcoCheckAPI.swift`: 서버 통신·Keychain 토큰
- `HistoryView.swift`: 기록 조회·삭제·서버 설정
- `shared/recycling-guides.json`(저장소 루트 기준): 앱 번들과 Java 서버가 함께 쓰는 안내 원본
- `EcoCheck/Fonts/LICENSE.txt`: Pretendard의 SIL Open Font License

Java 서버는 Windows/JDK 21/MySQL 8.0에서 실제 통합 테스트했습니다. Windows에서는 Xcode 빌드를 실행할 수 없으므로 Mac에서 다음 명령 또는 Xcode로 확인하세요. 실제 AI 정확도는 모델을 추가한 뒤 검증해야 합니다.

```sh
xcodebuild -project iOS/EcoCheck.xcodeproj -target EcoCheck -configuration Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
```
