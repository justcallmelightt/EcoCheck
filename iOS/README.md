# EcoCheck iOS — 첫 화면과 사진 선택

`EcoCheck.xcodeproj`를 Xcode에서 엽니다. Figma 홈 화면을 SwiftUI로 옮겼고, 스캔 버튼에서 사진을 고르면 미리보기를 표시합니다. AI 분석과 나머지 탭은 아직 연결하지 않았습니다.

- `EcoCheckApp.swift`: 앱 시작 시 번들에 포함된 Pretendard를 등록하고 `ContentView`를 보여줍니다.
- `ContentView.swift`: 홈 화면을 구성하고, `PhotosPicker`로 고른 사진을 `@State`에 저장해 미리보기에 표시합니다.
- `EcoCheck/Fonts/LICENSE.txt`: 앱에 포함된 Pretendard의 SIL Open Font License입니다.

이 로직을 이해한 뒤 다음 단계에서 사진 분석 요청을 연결합니다.
