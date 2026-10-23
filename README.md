![Swift](https://img.shields.io/badge/Swift-F05138?style=for-the-badge&logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/SwiftUI-007ACC?style=for-the-badge&logo=swift&logoColor=white)
![Java](https://img.shields.io/badge/Java-ED8B00?style=for-the-badge&logo=openjdk&logoColor=white)
![MySQL](https://img.shields.io/badge/MySQL-4479A1?style=for-the-badge&logo=mysql&logoColor=white)

# EcoCheck

스마트폰 카메라로 쓰레기를 스캔하면 인공지능이 물체를 인식하여, 재질별 분리배출 방법과 세척/라벨 제거 등의 구체적인 행동 지침을 즉각적으로 알려주는 사용자 맞춤형 에코 가이드 서비스.

> 일시: 10월 23일 오후 7:00 ~ 10월 24일 오후 12시

## 기여자

| 프로필 | GitHub | 역할 | 담당 |
| :---: | :---: | :---: | :--- |
| <img src="https://github.com/justcallmelightt.png" width="80"> | **권율**<br>([@justcallmelightt](https://github.com/justcallmelightt)) | **Team Leader <br> Full-Stack** [N%] | Front-end, Back-end, Design, Team Leader |
| <img src="https://github.com/ksm524923.png" width="80"> | **고성민**<br>([@ksm524923](https://github.com/ksm524923)) | **Back-end** [N%] | MySQL, Java |
| <img src="https://github.com/iioct.png" width="80"> | **이인서**<br>([@iioct](https://github.com/iioct)) | **Design** [N%] | UI 디자인 |


## 현재 개발 구조

- **iOS (SwiftUI + Core ML/Vision)**: 아이폰에서 사진을 분석하고 로컬 분리배출 안내를 표시합니다. 학습 모델은 아직 없으며 모델 연결 코드와 미준비 상태의 안내를 제공합니다.
- **Java (JDK HttpServer + JDBC, Spring Boot 미사용)**: 판별 결과 저장·조회·삭제, 총 기록 수를 제공합니다. VS Code에서 개발할 수 있습니다.
- **MySQL**: 분류별 안내와 기기별 기록을 저장합니다. 사진은 서버나 DB로 보내지 않습니다.

`아이폰 사진 → 아이폰 내부 AI → 로컬 안내 → 사용자가 저장 선택 → Java 서버 → MySQL`

실행은 [Java/MySQL 안내](backend/README.md), 모델 추가는 [iOS 안내](iOS/README.md)를 참고하세요. Windows에서 Java 서버를 개발·실행할 수 있고 iOS 빌드·실행에는 Mac/Xcode가 필요합니다. 기존 기획서의 모바일 웹에서 iOS 앱 + Java/MySQL 구조로 변경했습니다.
