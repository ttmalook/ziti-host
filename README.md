# Grav 기반 Zero Trust PoC 포털

> 이 포털에서 **MFA**, **마이크로세그먼테이션**, **세션 제어**, **Posture(단말 상태)** 를 실증합니다.  
> 아키텍처: **VM#1(OpenZiti: controller=quickstart, edge router)** ↔ **VM#2(Grav 포털 + ziti-host)**.
> VM1 설치 및 구성은 참고하세요.[Openziti.md](./Openziti.md)
> 상세 데모 절차는 [DEMO-GUIDE.md](./DEMO-GUIDE.md) 를 참고하세요.

컨테이너에서 **OpenZiti Edge Tunnel(호스트 모드)** 를 실행하기 위한 실무 가이드입니다.  
이미지에는 **실행 파일만 포함**하고, 아이덴티티(`web-host.json`)는 **런타임 볼륨 마운트**로 주입합니다.  
엔트리포인트는 아이덴티티를 `/run/ziti/`로 복사해 사용하여 파일 잠금 이슈를 회피합니다.

---

## ✅ 가장 빠른 실행 (GHCR **사전 빌드 이미지** 사용)

> 아래 순서를 그대로 따라하면 됩니다. (이미지/리포 준비 → Enroll → .env 수정 → 실행 → 검증)

### 1) 이미지/리포 **가져오기**
```bash
docker pull ghcr.io/ttmalook/ziti-host:1.7.10
git clone https://github.com/ttmalook/ziti-host.git
cd ziti-host && cp .env.example .env
```

### 2) 아이덴티티 **Enroll** (호스트에서 1회, JWT는 1회성)
> 이미 `/root/web-host.json` 이 있다면 이 단계는 **건너뜁니다.**
```bash
/root/ziti-bin/ziti edge enroll /root/web-host.jwt -o /root/web-host.json --rm
chmod 600 /root/web-host.json
```

### 3) **.env 수정**
```ini
# OpenZiti Controller의 실제 IP
CTRL_IP=192.168.56.105
# 호스트에 존재하는 아이덴티티 JSON 경로
IDENTITY_PATH=/root/web-host.json
```

### 4) **실행**
```bash
docker compose up -d
```

### 5) **상태 확인**
```bash
docker logs -f ziti-host
docker exec -it ziti-host /usr/local/bin/ziti-edge-tunnel tunnel_status
```

> (선택) 컨트롤러 연결 확인
```bash
curl -k https://$CTRL_IP:1280/edge/client/v1/version
```

> ℹ️ **왜 'quickstart' 호스트명이 필요한가?**  
> 컨트롤러 인증서의 CN/SAN 이 `quickstart` 이므로, 컨테이너 내부에서 `quickstart` 로 접속해야 TLS 검증이 정상 동작합니다.  
> 이 리포의 `docker-compose.yml` 은 `extra_hosts: ["quickstart:${CTRL_IP}"]` 로 자동 매핑합니다. (DNS 사용 시 생략 가능)

---

## 📁 리포 구조
```
.
├─ Dockerfile
├─ entrypoint.sh
├─ docker-compose.yml
├─ .env.example
├─ .gitignore
├─ .dockerignore
├─ Makefile
├─ README.md
└─ bin/
   └─ ziti-edge-tunnel   # 실행 바이너리(커밋 금지, 실행권한 필요)
```
- `entrypoint.sh` : `ziti` 그룹/소켓 준비 → 마운트된 JSON을 `/run/ziti/web-host.json`으로 복사 후 실행

---

## 🧪 트러블슈팅

- **`CONTROLLER_UNAVAILABLE / unknown node or service`**
  - compose의 `extra_hosts: ["quickstart:${CTRL_IP}"]` 확인
  - 연결 테스트: `curl -k https://$CTRL_IP:1280/edge/client/v1/version`
  - 인증서의 CN/SAN 과 접속 호스트명이 **일치**해야 함 (`quickstart` 권장)

- **Config Event 중 `resource busy or locked`**
  - 본 리포는 내부 사본(`/run/ziti/web-host.json`) 사용으로 회피됨

- **`local 'ziti' group not found` 경고**
  - 제어 소켓 권한 경고 → `entrypoint.sh`에서 그룹/디렉토리 생성으로 해결

- **시간 동기화 문제**
  - 호스트/컨테이너 시간 NTP 동기화 권장

- **Compose 문법 검증**
  - `docker compose config`

---

## 🔐 보안 수칙
- 커밋 금지: `*.jwt`, `web-host.json`, 인증서/키 (이미 `.gitignore` 포함)
- 아이덴티티 파일 권한 최소화: `chmod 600 /root/web-host.json`
- JWT는 1회성 → enroll 성공 시 `--rm` 로 즉시 삭제

---

## 📈 업그레이드/재배포
```bash
docker rm -f ziti-host || true
docker rmi ziti-host:1.7.10 || true
docker pull ghcr.io/ttmalook/ziti-host:1.7.10   # 또는 새 태그
docker compose up -d --pull always               # compose 사용 시
```

---

### ▶️ 전체 세부 가이드(올인원)
자세한 설치/아키텍처/정책/운영/트러블슈팅은 **[README-all-in-one.md](README-all-in-one.md)** 를 참조하세요.
