# Grav 기반 Zero Trust PoC 포털 — **검증/시연(데모) 가이드** _(OpenZiti)_

> 이 포털에서 **MFA**, **마이크로세그먼테이션(마이크로세그)**, **세션 제어**, **Posture(단말 상태)** 를 실증합니다.  
> 아키텍처: **VM#1(OpenZiti: controller=quickstart, edge router)** ↔ **VM#2(Grav 포털 + ziti-host)**.

---

## 0) 용어/가정
- **서비스(Service)**: Ziti 상에서 노출되는 L4 엔드포인트 단위(예: `portal.ziti:80`).
- **주체(Identity)**: 사용자/단말 또는 호스트(예: `desktop-client`, `newweb-host`).
- **정책(Policy)**: 어떤 주체가 어떤 서비스에 **Dial(접속)**/**Bind(호스팅)** 가능한지와 제약(MFA, Posture 등)을 정의.
- **Posture**: 단말의 상태(프로세스/OS/안티바이러스/시간 등)에 기반한 접속 조건.
- 표기: 컨트롤러 호스트명은 **`quickstart`**, IP는 예시로 **`192.168.56.105`** 사용.

---

## 1) 첨부 **검증 시나리오** ↔ 본 가이드 매핑
| 첨부 문서 항목 | 본 가이드 섹션 |
|---|---|
| 서비스 단위 **마이크로세그먼테이션 테스트** | §2 |
| **사용자 인증 및 MFA 적용 테스트** | §3 |
| **세션 실시간 제어 및 종료 테스트** | §4 |
| **Posture Check 기반 단말 조건 테스트** | §5 |
| (선택) 사용자/그룹별 라우터 분기·트래픽 분배 | §6 |

---

## 2) 서비스 단위 **마이크로세그먼테이션** 테스트
**목적:** 지정된 서비스만 탐지/접속 가능함을 확인 (권한 없는 서비스는 보이지 않음/접속 불가).

### 정책/구성
- **host.v1** (Grav 백엔드 바인드):  
  `{"protocol":"tcp","address":"grav","port":80}`
- **intercept.v1** (클라이언트 다이얼):  
  `{"addresses":["portal.ziti"],"portRanges":[{"low":80,"high":80}],"protocols":["tcp"]}`
- **Service:** `web-portal` ← `host.v1`, `intercept.v1`
- **Bind Policy:** 주체=`newweb-host` → 서비스=`web-portal`
- **Dial Policy:** 주체=`desktop-client(또는 그룹)` → 서비스=`web-portal`

### 실행(관리자)
```bash
# (템플릿) 서비스/정책 생성
ziti edge create config web-host host.v1  '{"protocol":"tcp","address":"grav","port":80}'
ziti edge create config web-intc intercept.v1 '{"addresses":["portal.ziti"],"portRanges":[{"low":80,"high":80}],"protocols":["tcp"]}'
ziti edge create service web-portal --configs web-host,web-intc
ziti edge create service-policy web-portal-bind Bind --service-roles @web-portal --identity-roles @newweb-host
ziti edge create service-policy web-portal-dial Dial --service-roles @web-portal --identity-roles @desktop-client
```

### 실행(사용자)
1. Desktop Edge 로그인
2. 브라우저에서 `http://portal.ziti` 접속

### 기대 결과 / 증적
- 접속 성공 → Grav 포털 페이지 표시
- 허용되지 않은 다른 서비스(예: `web-internal.company`)는 **탐지되지 않거나 접속 실패**
- **증적**: Desktop Edge 서비스 목록/로그, 컨트롤러 세션 생성 로그, 포털 화면 스크린샷

---

## 3) **MFA 적용** 테스트
**목적:** MFA 미적용 상태에서 차단되고, MFA 등록/검증 후에는 허용됨을 확인.

### 정책/구성
- Dial Policy에 **MFA 요구** 설정(컨트롤러 UI/CLI 기준; 버전에 따라 항목명이 다를 수 있음 → _환경에 맞춰 적용_).

### 실행(사용자)
1. **AS-IS:** Desktop Edge에서 `portal.ziti` 접근 → **MFA 미등록/미승인** 상태
2. Desktop Edge에서 **MFA(TOTP)** 등록/검증
3. **TO-BE:** 재접속

### 기대 결과 / 증적
- **AS-IS:** 접근 차단(Desktop Edge에 MFA 필요 메시지/로그)
- **TO-BE:** 접근 허용
- **증적**: MFA 등록 화면, 접근 성공/실패 로그, 컨트롤러 이벤트(‘MFA required/verified’)

> 참고: Desktop Edge CLI가 있는 경우 `enable_mfa`, `verify_mfa`, `get_mfa_codes` 등 명령을 사용해 증적을 남길 수 있습니다.

---

## 4) **세션 실시간 제어 및 종료** 테스트
**목적:** 접속 중인 세션을 **정책 변경으로 즉시 차단/종료** 가능한지 확인.

### 절차
1. 사용자 `desktop-client`가 `portal.ziti`에 접속하여 **세션 성립**
2. **관리자**가 아래 중 하나를 수행
   - Dial Policy에서 `desktop-client` 제거(또는 그룹 역할 제거)
   - `web-portal` 서비스를 **일시 비활성화**
3. 사용자는 새 요청 또는 페이지 새로고침 시 즉시 차단

### 기대 결과 / 증적
- Desktop Edge/브라우저: 연결 실패/세션 종료
- 컨트롤러 로그: 정책 변경에 따른 **접속 거부 기록**
- (선택) 세션 유지 조건에 **Posture** 포함 시, Posture 변화에 따른 즉시 차단도 확인

---

## 5) **Posture Check** 기반 단말 조건 테스트
**목적:** 보안 요건 미충족 단말을 차단하고, 요건 충족 시 허용됨을 확인.

### 예시 정책(중 하나 선택)
- **필수 프로세스 실행** 요구(예: `ziti-desktop-edge` 또는 사내 에이전트)
- **운영체제/패치 레벨** 요구
- **안티바이러스 동작** 요구

### 절차
1. Posture Query/Set을 정의하여 `Dial Policy`에 연결
2. **AS-IS:** 요건 **불충족** 상태에서 접속 시도 → 차단
3. **TO-BE:** 요건 충족(프로세스 실행/설치 등) 후 재접속 → 허용

### 기대 결과 / 증적
- 컨트롤러: Posture 평가 로그(예: `IsPassing=false → true`)
- Desktop Edge: Posture 요구/불일치 경고
- 증적: 전/후 스크린샷, 정책 스냅샷

---

## 6) (선택) 사용자/그룹별 **라우터 분기·트래픽 분배**
**목적:** 사용자 그룹에 따라 지정한 Edge Router로 **우회/분배**되는지 확인.

### 구성 아이디어
- 라우터에 역할 라벨 부여: `hq-router`, `branch-router`
- 서비스의 `edgeRouterRoles` 또는 정책을 통해 대상 라우터 **제한/우선**
- 그룹 A → `hq-router`, 그룹 B → `branch-router` 로 분기

### 기대 결과 / 증적
- 라우터별 세션/트래픽 분포가 정책에 따라 변화
- 컨트롤러/라우터 로그: 어떤 경로가 선택되었는지 식별

---

## 7) 운영 체크리스트
```bash
# 터널 상태
docker logs -f ziti-host
docker exec -it ziti-host /usr/local/bin/ziti-edge-tunnel tunnel_status

# 컨트롤러 헬스
curl -k https://192.168.56.105:1280/edge/client/v1/version
```

---

## 8) 증적 수집 가이드
- **정책 스냅샷**: 서비스/정책/포스처 설정 화면 캡처
- **접속 로그**: Desktop Edge 로그 + 컨트롤러 이벤트
- **화면 캡처**: Grav 포털 접속 성공/실패 화면, MFA 등록/검증 화면
- **시간 동기화**: 시간 불일치로 인한 오탐 방지(NTP 권장)

---

## 9) 롤백
- 테스트용 정책/서비스는 `disable` 또는 삭제
- 사용/테스트용 아이덴티티는 `suspend` 또는 삭제
- 변경 이력은 내역서에 정리

---

### 부록: 핵심 템플릿(요약)
```bash
# 서비스/정책 최소 셋업
ziti edge create config web-host host.v1  '{"protocol":"tcp","address":"grav","port":80}'
ziti edge create config web-intc intercept.v1 '{"addresses":["portal.ziti"],"portRanges":[{"low":80,"high":80}],"protocols":["tcp"]}'
ziti edge create service web-portal --configs web-host,web-intc
ziti edge create service-policy web-portal-bind Bind --service-roles @web-portal --identity-roles @newweb-host
ziti edge create service-policy web-portal-dial Dial --service-roles @web-portal --identity-roles @desktop-client
```
