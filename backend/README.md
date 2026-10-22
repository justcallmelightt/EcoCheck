# EcoCheck Java + MySQL

Spring Boot 없이 **JDK HttpServer + JDBC + MySQL**로 만든 기록 저장 서버입니다. VS Code에서 개발·실행할 수 있습니다. 사진 분석은 iOS Core ML/Vision이 담당하고 서버에는 사진을 보내지 않습니다.

## 준비와 실행

- JDK 17 이상, VS Code의 Extension Pack for Java, MySQL Server 8.0 이상이 필요합니다. 현재 PC에는 모두 설치되어 있습니다.
- MySQL Workbench는 DB를 보는 도구이고 실제 저장에는 MySQL Server가 필요합니다.
- Maven은 별도 설치 없이 공식 `mvnw.cmd`/`mvnw`를 사용합니다. 처음에는 인터넷이 필요합니다.
- 저장소 최상위 폴더를 VS Code에서 열면 `.vscode`의 빌드·테스트·디버그 설정을 사용할 수 있습니다.

Windows에서 기존 MySQL과 충돌 없이 실행:

```powershell
cd backend
.\scripts\start-local-mysql.ps1
.\mvnw.cmd package
java -jar target/ecocheck-server-0.1.0.jar
```

도우미는 설치된 MySQL 실행 파일로 **별도 로컬 인스턴스**를 만듭니다. 기존 `MySQL80` 서비스나 DB는 수정하지 않습니다. `127.0.0.1:33316`에서 실행하고 무작위 비밀번호, 전용 사용자, `ecocheck`/`ecocheck_test` DB를 준비합니다. 데이터는 `.data/`, 연결 설정은 `.env`에 보관하며 모두 Git에서 제외됩니다. 기존 `.env`가 있으면 덮어쓰지 않고 중단합니다.

MySQL 위치가 다르면 `-MySqlBin 'D:\MySQL\bin'`, 포트가 사용 중이면 **최초 실행 때** `-Port 33317`을 지정하세요. 다시 시작할 때도 동일한 포트를 사용합니다. 종료 시 서버는 Ctrl+C, DB는 `.\scripts\stop-local-mysql.ps1`을 사용합니다. 데이터는 유지됩니다.

`java`가 인식되지 않으면 VS Code의 **Java: Configure Java Runtime**에서 JDK를 선택하고 터미널의 `JAVA_HOME`/`PATH`도 확인하세요. 이 PC에서는 다음처럼 설정할 수 있습니다. 다른 PC에서는 실제 설치 경로로 바꾸세요.

```powershell
$env:JAVA_HOME = 'C:\Program Files\Java\jdk-21.0.10'
$env:Path = "$env:JAVA_HOME\bin;$env:Path"
```

## 직접 MySQL 설정 / macOS·Linux

관리 계정으로 Workbench 등에서 실행합니다. 비밀번호는 본인이 정한 값으로 바꾸세요.

```sql
CREATE DATABASE ecocheck CHARACTER SET utf8mb4;
CREATE USER 'ecocheck'@'127.0.0.1' IDENTIFIED BY 'CHANGE_THIS_PASSWORD';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, REFERENCES ON ecocheck.* TO 'ecocheck'@'127.0.0.1';
```

`.env.example`을 `.env`로 복사하고 DB URL·사용자·비밀번호를 수정합니다. 서버는 **backend 폴더**의 `.env`를 읽으며 환경변수가 우선합니다. 따옴표로 감싼 값은 지원하고 줄 끝 주석은 지원하지 않습니다. 시작할 때 `schema.sql`로 테이블을 만들고 공통 안내 JSON을 DB에 넣습니다.

macOS/Linux에서는 `chmod +x mvnw`, `./mvnw package`, `java -jar target/ecocheck-server-0.1.0.jar`를 사용하세요.

## API

| 방식 | 주소 | 기능 |
|---|---|---|
| GET | `/health` | MySQL 연결까지 확인. 실패 시 503 |
| GET | `/api/v1/categories` | 기본 분류와 단계별 안내 |
| POST | `/api/v1/scans` | 아이폰의 판별 결과 저장 |
| GET | `/api/v1/scans?limit=50&offset=0` | 이 기기의 최신 기록 |
| DELETE | `/api/v1/scans/{id}` | 이 기기의 기록 삭제 |
| GET | `/api/v1/statistics` | 이 기기의 총 저장 기록 수 |

기록·통계에는 `Authorization: Bearer <64자리 소문자 16진수 토큰>`이 필요합니다. iOS가 보안 난수 토큰을 생성해 Keychain에 저장하고 서버는 SHA-256 해시로 기록을 구분합니다. 회원 계정이나 기기 간 동기화는 아직 없습니다. 토큰을 잃으면 기존 기록에 접근할 수 없습니다. DB에는 사진·토큰 원문을 저장하지 않습니다.

POST 본문:

```json
{"id":"12345678-1234-1234-1234-123456789012","categoryId":"pet_bottle","confidence":0.95,"modelVersion":"1.0.0"}
```

정확히 위 4개 필드만 허용합니다. 최대 4096바이트, 신뢰도 `0.7~1`, 모델 버전은 영문·숫자로 시작하는 영문·숫자·`.`·`_`·`-` 80자 이내입니다. 알려진 category ID만 받습니다. 첫 저장은 201, 같은 토큰·UUID·내용 재전송은 200, 같은 UUID의 다른 내용은 409입니다. 실패 후 재시도할 때 UUID를 바꾸지 마세요. 저장 시각은 서버 UTC입니다.

조회 응답은 `{ "items": [...], "total": 2, "limit": 50, "offset": 0 }`이며 limit은 1~100, offset은 0~10000입니다. 오류는 `{ "error": { "code": "...", "message": "..." } }`입니다. SQL에는 PreparedStatement를 사용합니다.

`shared/recycling-guides.json`의 ID 5개가 현재 계약입니다: `pet_bottle`, `aluminum_can`, `steel_can`, `glass_bottle`, `cardboard`. 안내는 개발용 기본값이므로 지역별 검토가 필요합니다. 계획한 15종은 데이터 수집·학습·안내 검토 후 공통 파일과 테스트를 함께 확장하세요.

클라이언트 분류의 진위를 서버에서 증명할 수 없으므로 기록을 실제 분리배출 완료·포인트 지급 근거로 사용하지 않습니다. 탄소 절감량·포인트 계산·로그인·지도는 아직 구현하지 않았습니다.

## 아이폰 연결

아이폰은 Java 서버에만 접근하며 MySQL에 직접 연결하지 않습니다. AI 판별과 기본 안내는 서버 없이 사용하는 구조이고 실제 학습 모델은 아직 없습니다.

- 실제 아이폰에서는 PC의 `127.0.0.1`로 접근할 수 없습니다. 같은 Wi-Fi에서 `.env`의 `ECOCHECK_HOST=0.0.0.0`으로 바꾸고 서버를 다시 시작한 뒤 앱 **설정**에 `http://PC의사설IP:8080`을 입력하세요. Windows 방화벽에서 개인 네트워크의 서버 포트를 허용해야 할 수 있습니다.
- MySQL은 계속 `127.0.0.1`에 둡니다.
- 로컬 HTTP는 Debug 개발용입니다. Release에서는 HTTPS만 허용합니다. 외부 공개 시에는 HTTPS 역방향 프록시와 접근·요청량 제한 등을 구성하세요. 현재는 로컬 개발 서버입니다.

## 테스트

`.\mvnw.cmd test`는 API 검증 테스트를 실행합니다. 별도 MySQL 정보가 없으면 DB 통합 테스트 1개를 건너뜁니다. 결과의 `Skipped`를 확인하세요.

로컬 도우미로 만든 별도 `ecocheck_test` DB까지 검증:

```powershell
Get-Content .env | ForEach-Object {
  if ($_ -match '^ECOCHECK_DB_(URL|USER|PASSWORD)=(.*)$') {
    [Environment]::SetEnvironmentVariable('ECOCHECK_TEST_DB_' + $Matches[1], $Matches[2].Replace('/ecocheck?', '/ecocheck_test?'), 'Process')
  }
}
.\mvnw.cmd verify
```

직접 DB를 구성했다면 별도 테스트 DB와 권한을 만들고 `ECOCHECK_TEST_DB_URL`, `ECOCHECK_TEST_DB_USER`, `ECOCHECK_TEST_DB_PASSWORD`를 설정하세요. 실제 사용자 DB를 테스트에 지정하지 마세요. 통합 테스트는 무작위 기기 토큰의 기록만 만들고 삭제하며 재시작 후 유지·기기 분리·중복 요청·삭제·한국어 저장을 확인합니다.

참고: [JDK HttpServer](https://docs.oracle.com/en/java/javase/26/docs/api/jdk.httpserver/com/sun/net/httpserver/HttpServer.html), [MySQL Connector/J](https://dev.mysql.com/doc/connector-j/en/connector-j-installing-maven.html), [Apple Vision + Core ML](https://developer.apple.com/documentation/coreml/classifying-images-with-vision-and-core-ml).
