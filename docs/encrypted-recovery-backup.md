# 인증 정보 포함 암호화 복구 백업

이 절차는 비밀번호 해시·세션·갱신 토큰을 포함한다. 사용자가 2026-09-13에 이 범위의 암호화 백업을 명시적으로 승인했다. 운영 DB는 읽기만 하며, 자격 증명이나 SQL 데이터를 콘솔·로그·평문 파일에 출력하지 않는다.

## 보관 방식

- `tools/ops/encrypted-recovery-backup.py`는 연결 프로젝트를 확인한 뒤 `public`, `auth`, `storage`, `supabase_migrations` 스키마와 데이터를 메모리에 덤프한다.
- ZIP 압축 후 AES-256-GCM으로 암호화한다. 무작위 256비트 키는 현재 Windows 사용자 DPAPI로 감싼다. 디렉터리 접근 권한은 현재 사용자와 SYSTEM으로 제한한다.
- 결과는 Git에서 제외한 `.local-backups/encrypted-recovery-<UTC>/recipe-scout-recovery.encrypted.json`이다. 복호화 일치·내부 SHA-256·변조 거부를 검증한다.
- 별도 암호를 채팅에 전달하지 않는다. **이 파일만 다른 PC에 복사해도 복구할 수 있는 방식은 아니다.** 현재 Windows 계정의 DPAPI 키와 정상적인 계정 접근을 잃으면 복호화하지 못할 수 있다. 컴퓨터 분실에 대비한 공급자 백업 또는 별도 키 관리가 있는 외부 백업은 여전히 필요하다.
- 애플리케이션이 평문 SQL 파일을 생성하지 않는다는 뜻이며, 운영체제의 메모리/페이지 파일·디스크 암호화까지 이 스크립트가 관리하는 것은 아니다.

## 실행 및 검증

저장된 Supabase CLI 인증, Docker Desktop, Python `cryptography`가 필요하다. 저장소 루트에서 실행한다. 인증 정보가 포함된 백업의 생성과 복원에는 명시적 승인이 필요하다.

```powershell
$env:PYTHONUTF8='1'
& 'C:/Users/ADMIN/AppData/Local/Programs/Python/Python312/python.exe' tools/ops/encrypted-recovery-backup.py create
```

기존 암호화 파일의 복호화와 내부 무결성만 확인하려면 다음을 실행한다. `<백업 파일>`에는 실제 경로를 사용한다.

```powershell
& 'C:/Users/ADMIN/AppData/Local/Programs/Python/Python312/python.exe' tools/ops/encrypted-recovery-backup.py verify --backup '<백업 파일>'
```

실제 DB 복원 시험:

```powershell
& 'C:/Users/ADMIN/AppData/Local/Programs/Python/Python312/python.exe' tools/ops/verify-encrypted-recovery.py '<백업 파일>'
```

검증 도구는 Supabase PostgreSQL 17.6.1.147 이미지의 새 컨테이너 하나를 만든다. 외부 네트워크와 공개 포트가 없고 루트 파일시스템은 읽기 전용이며 DB는 tmpfs에만 저장된다. 컨테이너 로그도 비활성화한다. 스키마·데이터를 복원하고 COPY 대상 모든 테이블의 전체 행을 비교한 뒤 `finally`에서 자신이 만든 컨테이너만 제거한다. 기존 개발/운영 DB는 변경하지 않는다. 도구가 강제 종료되거나 Docker 자체가 중단되면 자동 정리가 실행되지 않을 수 있으므로 해당 작업이 만든 `recipe-scout-offline-restore-` 컨테이너가 남았는지 확인한다. 기존 Supabase 컨테이너를 삭제하지 않는다.

## 검증 범위와 복구 시 주의점

- 실제 Auth 스키마와 사용자·세션·토큰 데이터를 복원한다. Auth 대체 테이블을 이용한 이전 public 전용 시험과 다르다.
- 스키마 덤프와 데이터 덤프는 별도 시점이다. 배포/스키마 변경이 진행되지 않는 때에 실행한다. 데이터 덤프 내 테이블은 한 번의 덤프에서 수집한다.
- DB 역할의 비밀번호, Supabase 프로젝트 JWT/암호화 비밀, OAuth·메일·Firebase·Play 설정, 스토리지 파일 본체, Edge Function 배포 자체는 이 아카이브에 포함하지 않는다. 스토리지 메타데이터만으로 이미지 파일을 복구할 수 없다.
- 실제 로그인·갱신·OAuth·메일 발송 시험은 별도로 필요하다. 다른 프로젝트에서는 원래 세션/JWT가 그대로 유효하다고 보장할 수 없다. 실제 사고 복구에서는 유출 가능성과 복구 시점을 평가하고 기존 세션을 폐기해 재로그인을 요구할 수 있다.
- 이는 수동 시점 백업이다. 자동 일일 백업, 오프사이트 보관, PITR 또는 RPO/RTO 보장을 구성한 것은 아니다.

검증 증거는 `.artifacts/security-encrypted-backup-result.json`과 `.artifacts/security-encrypted-restore-result.json`, 당일 결과는 `docs/security-rollout-2026-09-13.md`에 기록한다.
