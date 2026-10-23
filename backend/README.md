# EcoCheck Java 서버

IntelliJ에서 이 폴더의 pom.xml을 Maven 프로젝트로 등록한 뒤 `kr.ecocheck.EcoCheckServerApplication.main`을 실행합니다. Java 17 이상입니다.

- **SETUP.md**: MySQL Workbench 설정, API 발급, 서울시 쓰레기통 데이터 적재
- **API.md**: 요청·응답, 기존 iOS에서 바꿀 부분
- **TEST-RESULTS.md**: 실제 검증 결과와 미검증 항목
- **requests.http**: IntelliJ에서 바로 실행할 API 요청
- **sql/schema.sql**: Workbench에서 실행할 DB 스크립트
- **.env.example**: `.env`로 복사해 DB 계정과 API 키 입력

왜 이렇게 파일을 나눴는지는 상위 README.md에 설명했습니다.
