# ziti-host (OpenZiti Edge Tunnel in Docker) — All-in-One README (Grav 기반 Zero Trust PoC 포털)

> 이 포털에서 **MFA**, **마이크로세그먼테이션(마이크로세그)**, **세션 제어**, **Posture(단말 상태)** 를 실증합니다.  
> 아키텍처: **VM#1(OpenZiti: controller=quickstart, edge router)** ↔ **VM#2(Grav 포털 + ziti-host)**.  
> 데모 절차는 `[DEMO-GUIDE.md](./DEMO-GUIDE.md)` 를 참고하세요.

컨테이너에서 **OpenZiti Edge Tunnel(호스트 모드)** 를 실행하기 위한 실무용 문서입니다.  
이미지에는 **실행 파일만 포함**하고, 아이덴티티(`web-host.json`)는 **런타임 볼륨 마운트**로 주입합니다.  
엔트리포인트는 아이덴티티를 `/run/ziti/`로 복사해 사용하여 파일 잠금 이슈를 회피합니다.

---

## 목차
- [구조](#구조)
- [환경 변수 레퍼런스](#환경-변수-레퍼런스)
- [사전 준비](#사전-준비)
- [빠른 시작 (TL;DR)](#빠른-시작-tldr)
- [빌드](#빌드)
- [실행 (docker run)](#실행-docker-run)
- [실행 (docker-compose)](#실행-docker-compose)
- [GitHub Actions(CI) — 이미지 빌드/푸시](#github-actionsci--이미지-빌드푸시)
- [Kubernetes 배포 예시(Secret 주입)](#kubernetes-배포-예시secret-주입)
- [상태 확인 & 운영](#상태-확인--운영)
- [HEALTHCHECK 추가(선택)](#healthcheck-추가선택)
- [OpenZiti 서비스/정책 예시](#openziti-서비스정책-예시)
- [트러블슈팅](#트러블슈팅)
- [보안 수칙](#보안-수칙)
- [업그레이드/재배포](#업그레이드재배포)
- [FAQ](#faq)

---

## 구조
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

## 환경 변수 레퍼런스
| 변수 | 기본값/예시 | 설명 |
|---|---|---|
| `CTRL_IP` | `192.168.56.105` | 컨트롤러 IP. 컨테이너에 `quickstart:CTRL_IP`로 매핑 |
| `IDENTITY_PATH` | `/root/web-host.json` | 호스트의 아이덴티티 JSON 경로 |
| `IDENTITY_FILE` | `/etc/ziti/web-host.json` | 컨테이너 내부에서 읽을 경로(엔트리포인트가 /run/ziti 로 복사) |
| `GRAV_IMAGE` | `ghcr.io/OWNER/grav:TAG` | (선택) Grav 포털 이미지 태그(Compose 동시 기동 시) |

---

## 사전 준비
1) **호스트에서 1회 Enroll** (JWT는 1회성)
```bash
/root/ziti-bin/ziti edge enroll /root/web-host.jwt -o /root/web-host.json --rm
chmod 600 /root/web-host.json
```
2) **컨트롤러 호스트명 매핑**  
인증서 CN/SAN이 `quickstart` 라면 컨테이너에 `quickstart:<IP>` 매핑이 필요합니다.

> 연결 확인(선택)
```bash
curl -k https://<CTRL_IP>:1280/edge/client/v1/version
```

---

## 빠른 시작 (TL;DR)
```bash
# 1) 바이너리 준비
chmod +x ./bin/ziti-edge-tunnel

# 2) 이미지 빌드
docker build -t ziti-host:1.7.10 .

# 3) 실행
export CTRL_IP=192.168.56.105
export IDENTITY_PATH=/root/web-host.json
docker run -d --name ziti-host   --add-host quickstart:$CTRL_IP   -v $IDENTITY_PATH:/etc/ziti/web-host.json   --restart always   ziti-host:1.7.10

# 4) 상태 확인
docker logs -f ziti-host
docker exec -it ziti-host /usr/local/bin/ziti-edge-tunnel tunnel_status
```

---

## 빌드
**로컬 바이너리 사용**
```bash
# ./bin/ziti-edge-tunnel 존재 & 실행권한 필요
docker build -t ziti-host:1.7.10 .
```

**Makefile 사용(선택)**
```bash
make build TAG=1.7.10
# 원격에서 바이너리 받기(옵션)
make fetch URL="https://example.com/path/to/ziti-edge-tunnel"
make build TAG=1.7.10
```

---

## 실행 (docker run)
```bash
export CTRL_IP=192.168.56.105
export IDENTITY_PATH=/root/web-host.json

docker run -d --name ziti-host   --add-host quickstart:$CTRL_IP   -v $IDENTITY_PATH:/etc/ziti/web-host.json   --restart always   ziti-host:1.7.10
```
- 마운트된 `/etc/ziti/web-host.json` 은 엔트리포인트에서 `/run/ziti/web-host.json` 으로 복사되어 사용됩니다.

---

## 실행 (docker-compose)
### A) **ziti-host 단독** (기본)
```yaml
services:
  ziti-host:
    build: .
    image: ziti-host:1.7.10
    container_name: ziti-host
    volumes:
      - ${IDENTITY_PATH:-/root/web-host.json}:/etc/ziti/web-host.json:ro
    extra_hosts:
      - "quickstart:${CTRL_IP}"
    restart: always
    healthcheck:
      test: [ "CMD", "/usr/local/bin/ziti-edge-tunnel", "tunnel_status" ]
      interval: 30s
      timeout: 5s
      retries: 3
```
### B) **Grav + ziti-host 동시 기동** (포털 PoC 권장)
```yaml
services:
  grav:
    image: ${GRAV_IMAGE}
    container_name: grav
    networks: [ ziti-net ]

  ziti-host:
    build: .
    image: ziti-host:1.7.10
    container_name: ziti-host
    volumes:
      - ${IDENTITY_PATH:-/root/web-host.json}:/etc/ziti/web-host.json:ro
    extra_hosts:
      - "quickstart:${CTRL_IP}"
    restart: always
    healthcheck:
      test: [ "CMD", "/usr/local/bin/ziti-edge-tunnel", "tunnel_status" ]
      interval: 30s
      timeout: 5s
      retries: 3
    networks: [ ziti-net ]

networks:
  ziti-net: { driver: bridge }
```
실행:
```bash
cp .env.example .env   # CTRL_IP, IDENTITY_PATH, (선택)GRAV_IMAGE 수정
docker compose config  # 문법/구성 검증
docker compose up -d --build
docker compose logs -f
```

---

## GitHub Actions(CI) — 이미지 빌드/푸시
`.github/workflows/docker-image.yml` 예시(ghcr 기준):
```yaml
name: build-and-push
on:
  push:
    branches: [ "main" ]
    paths:
      - "Dockerfile"
      - "entrypoint.sh"
      - ".github/workflows/docker-image.yml"
      - "bin/**"
permissions:
  contents: read
  packages: write
jobs:
  docker:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-qemu-action@v3
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: ghcr.io/${{ github.repository_owner }}/ziti-host:1.7.10
```

---

## Kubernetes 배포 예시(Secret 주입)
`k8s/ziti-host.yaml` 템플릿:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: ziti-identity
type: Opaque
data:
  # web-host.json 내용을 base64로 인코딩하여 'web-host.json' 키에 넣으세요.
  web-host.json: REPLACE_WITH_BASE64
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ziti-host
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ziti-host
  template:
    metadata:
      labels:
        app: ziti-host
    spec:
      # 컨트롤러 인증서의 CN/SAN이 quickstart일 때 필요
      hostAliases:
        - ip: "192.168.56.105"  # <- CTRL_IP
          hostnames: ["quickstart"]
      containers:
        - name: ziti-host
          image: ghcr.io/OWNER/ziti-host:1.7.10  # 레지스트리 경로로 교체
          imagePullPolicy: IfNotPresent
          volumeMounts:
            - name: id
              mountPath: /etc/ziti
              readOnly: true
          readinessProbe:
            exec:
              command: ["/usr/local/bin/ziti-edge-tunnel","tunnel_status"]
            initialDelaySeconds: 5
            periodSeconds: 15
          resources:
            requests: { cpu: "50m", memory: "64Mi" }
            limits:   { cpu: "500m", memory: "256Mi" }
      volumes:
        - name: id
          secret:
            secretName: ziti-identity
            items:
              - key: web-host.json
                path: web-host.json
```
적용 전 검증/생성:
```bash
# Secret 생성(실제 파일 사용)
kubectl create secret generic ziti-identity   --from-file=web-host.json=/root/web-host.json -n default   --dry-run=client -o yaml | kubectl apply -f -

# 매니페스트 드라이런
kubectl apply -f k8s/ziti-host.yaml --dry-run=client
```

---

## 상태 확인 & 운영
```bash
docker ps
docker logs -f ziti-host
docker exec -it ziti-host /usr/local/bin/ziti-edge-tunnel tunnel_status

# 로그 레벨 임시 변경
docker exec -it ziti-host /usr/local/bin/ziti-edge-tunnel set_log_level debug

# 재시작/정리
docker restart ziti-host
docker rm -f ziti-host
```
**정상 로그 힌트**
- `identity ... loaded`
- `connected to controller ...`
- `router ... connected`

---

## HEALTHCHECK 추가(선택)
`Dockerfile` 하단 예시:
```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --retries=3 CMD   /usr/local/bin/ziti-edge-tunnel tunnel_status | grep -q '"Active":true' || exit 1
```
> 간단히 실행 성공만 보려면 compose 예시의 `CMD tunnel_status` 헬스체크로도 충분합니다.

---

## OpenZiti 서비스/정책 예시

### (추천) **컨테이너 간 통신** — Grav 동시 기동 시
**host.v1**
```json
{"protocol":"tcp","address":"grav","port":80}
```
**intercept.v1**
```json
{"addresses":["portal.ziti"],"portRanges":[{"low":80,"high":80}],"protocols":["tcp"]}
```
**CLI 템플릿**
```bash
ziti edge create config web-host host.v1  '{"protocol":"tcp","address":"grav","port":80}'
ziti edge create config web-intc intercept.v1 '{"addresses":["portal.ziti"],"portRanges":[{"low":80,"high":80}],"protocols":["tcp"]}'
ziti edge create service web-portal --configs web-host,web-intc
ziti edge create service-policy web-portal-bind Bind --service-roles @web-portal --identity-roles @newweb-host
ziti edge create service-policy web-portal-dial Dial --service-roles @web-portal --identity-roles @desktop-client
```

### (대안) **호스트 루프백** — Grav가 호스트의 `127.0.0.1:80` 일 때
**host.v1**
```json
{"protocol":"tcp","address":"127.0.0.1","port":80}
```
**intercept.v1**
```json
{"addresses":["portal.ziti"],"portRanges":[{"low":80,"high":80}],"protocols":["tcp"]}
```

---

## 트러블슈팅
- **CONTROLLER_UNAVAILABLE / unknown node or service**
  - `--add-host quickstart:<IP>` 또는 compose의 `extra_hosts` 확인
  - 접근 확인: `curl -k https://<CTRL_IP>:1280/edge/client/v1/version`
  - 인증서 CN/SAN과 호스트명 일치 필요(아이덴티티를 IP로 바꾸면 TLS 검증 실패 가능)

- **Config Event 중 `resource busy or locked`**
  - 본 리포는 내부 사본(`/run/ziti/`) 사용으로 회피됨

- **`local 'ziti' group not found`**
  - 제어 소켓 권한 경고 → `entrypoint.sh`에서 그룹/디렉토리 생성으로 해결

- **시간 오차로 인증 실패**
  - 호스트/컨테이너 시간 NTP 동기화 권장

- **Compose/K8s 문법 검증**
  - `docker compose config`
  - `kubectl apply -f k8s/ziti-host.yaml --dry-run=client`

---

## 보안 수칙
- 절대 커밋 금지: `*.jwt`, `web-host.json`, 인증서/키 (이미 `.gitignore` 포함)
- 아이덴티티 파일 권한 최소화
```bash
chmod 600 /root/web-host.json
```
- JWT는 1회성 → enroll 성공 시 `--rm` 로 즉시 삭제
- (선택) 컨테이너 하드닝:
```yaml
# compose 예시
security_opt:
  - no-new-privileges:true
read_only: true
tmpfs:
  - /tmp
```

---

## 업그레이드/재배포
```bash
docker rm -f ziti-host
docker rmi ziti-host:1.7.10
docker build -t ziti-host:1.7.10 .
docker run -d --name ziti-host   --add-host quickstart:$CTRL_IP   -v $IDENTITY_PATH:/etc/ziti/web-host.json   --restart always   ziti-host:1.7.10
```
> 버전 태그를 올리고(예: `1.7.11`) 레지스트리에 push/pull 해도 됩니다.

---

## FAQ
**Q. 컨테이너 안에서 enroll까지 자동화할 수 있나요?**  
가능은 하지만 JWT가 1회성이라 재시작/롤백 시 꼬일 수 있습니다. 권장: **외부에서 1회 enroll → JSON만 마운트**.

**Q. 바이너리를 Git에 넣어도 되나요?**  
보안/용량 이슈로 **비권장**. 로컬 `bin/`에 두고 빌드하세요.

**Q. Podman으로도 동작하나요?**  
가능합니다. `podman-docker` 환경이면 대부분 동일하게 동작합니다.
