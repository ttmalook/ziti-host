# Grav 기반 Zero Trust PoC 포털 — README-all-in-one

> 이 포털에서 **MFA**, **마이크로세그먼테이션**, **세션 제어**, **Posture(단말 상태)** 를 실증합니다.  
> 아키텍처: **VM#1(OpenZiti: controller=quickstart, edge router)** ↔ **VM#2(Grav 포털 + ziti-host)**.  
> 데모 절차는 `DEMO-GUIDE.md` 를 참고하세요.

컨테이너에서 **OpenZiti Edge Tunnel(호스트 모드)** 를 실행하기 위한 실무형 가이드입니다.  
이미지에는 **실행 파일만 포함**하고, 아이덴티티(`web-host.json`)는 **런타임 볼륨 마운트**로 주입합니다.  
엔트리포인트는 아이덴티티를 `/run/ziti/`로 복사해 사용하여 파일 잠금 이슈를 회피합니다.

---

## 목차
- [개요 & 목표](#개요--목표)
- [아키텍처 & 흐름](#아키텍처--흐름)
- [역할/아이덴티티 매트릭스](#역할아이덴티티-매트릭스)
- [사전 요구사항](#사전-요구사항)
- [가장 빠른 실행(GHCR)](#가장-빠른-실행ghcr)
- [아이덴티티 Enroll & 관리](#아이덴티티-enroll--관리)
- [환경 변수 레퍼런스](#환경-변수-레퍼런스)
- [실행 방법](#실행-방법)
- [Grav 연동 패턴](#grav-연동-패턴)
- [OpenZiti 서비스/정책 예시](#openziti-서비스정책-예시)
- [Kubernetes 배포 예시](#kubernetes-배포-예시)
- [운영 & 관찰성](#운영--관찰성)
- [트러블슈팅](#트러블슈팅)
- [보안 수칙](#보안-수칙)
- [CI/CD (선택)](#cicd-선택)
- [버전/호환성/성능](#버전호환성성능)
- [알려진 제한/주의사항](#알려진-제한주의사항)
- [부록](#부록)

---

## 개요 & 목표
- Grav 기반 포털을 **Zero Trust**로 노출(공인 IP/포트 개방 없이 접근).  
- 실증 항목: **MFA**, **마이크로세그**, **세션 제어**, **Posture**.  
- 성공 기준: 외부 단말은 Desktop Edge Client로 인증 후 `portal.ziti:80`에서 포털 접근, 정책 변경이 즉시 반영.

## 아키텍처 & 흐름
```
Desktop Edge Client ──(mTLS)── Controller(quickstart:1280)
                                  │
                                  └── Edge Router
                                          │
                                      ziti-host (run-host)
                                          │
                                         Grav
```
- 컨트롤러 인증서의 CN/SAN이 `quickstart` → 컨테이너 내부에서 `quickstart`로 접속(Compose의 `extra_hosts`가 매핑).

## 역할/아이덴티티 매트릭스
| 역할 | 예시 아이덴티티 | 권한 |
|---|---|---|
| Grav 호스트 터널 | `newweb-host` | 특정 서비스 **Bind** |
| 사용자 단말 | Desktop Edge Client | 해당 서비스 **Dial** |
| 컨트롤 평면 | Controller/Edge Router | 인증/라우팅 |

## 사전 요구사항
- Docker(또는 Podman), 네트워크 연결(컨트롤러 `1280/tcp`), 시간 동기화(NTP 권장).  
- 컨트롤러 인증서 CN/SAN=`quickstart` (DNS로 풀리거나 `extra_hosts` 매핑 필요).  
- 리소스 가이드: 최소 1 vCPU / 256MiB RAM.

## 가장 빠른 실행(GHCR)
```bash
docker pull ghcr.io/ttmalook/ziti-host:1.7.10
git clone https://github.com/ttmalook/ziti-host.git
cd ziti-host && cp .env.example .env
# .env 수정: CTRL_IP, IDENTITY_PATH
docker compose up -d

# 검증
docker logs -f ziti-host
docker exec -it ziti-host /usr/local/bin/ziti-edge-tunnel tunnel_status
curl -k https://$CTRL_IP:1280/edge/client/v1/version   # 선택
```

## 아이덴티티 Enroll & 관리
```bash
# 호스트에서 1회(이미 web-host.json 있으면 생략)
/root/ziti-bin/ziti edge enroll /root/web-host.jwt -o /root/web-host.json --rm
chmod 600 /root/web-host.json
```
- JWT는 **1회성**. 재발급/교체 시 컨테이너 재시작 필요.

## 환경 변수 레퍼런스
| 변수 | 예시/기본 | 설명 |
|---|---|---|
| `CTRL_IP` | `192.168.56.105` | 컨트롤러 IP (`quickstart` 매핑에 사용) |
| `IDENTITY_PATH` | `/root/web-host.json` | 호스트의 아이덴티티 JSON 경로 |
| `IDENTITY_FILE` | `/etc/ziti/web-host.json` | 컨테이너 내부 읽기 경로 |
| `GRAV_IMAGE` | `lscr.io/linuxserver/grav:latest` | (선택) Grav 이미지 |

## 실행 방법
### docker run
```bash
export CTRL_IP=192.168.56.105
export IDENTITY_PATH=/root/web-host.json
docker run -d --name ziti-host   --add-host quickstart:$CTRL_IP   -v $IDENTITY_PATH:/etc/ziti/web-host.json:ro   --restart always   ghcr.io/ttmalook/ziti-host:1.7.10
```
### docker-compose (단독)
```yaml
services:
  ziti-host:
    image: ghcr.io/ttmalook/ziti-host:1.7.10
    container_name: ziti-host
    volumes:
      - ${IDENTITY_PATH:-/root/web-host.json}:/etc/ziti/web-host.json:ro
    extra_hosts:
      - "quickstart:${CTRL_IP}"
    restart: always
```
### docker-compose (Grav 동시 기동)
```yaml
services:
  grav:
    image: ${GRAV_IMAGE}
    container_name: grav
    networks: [ ziti-net ]

  ziti-host:
    image: ghcr.io/ttmalook/ziti-host:1.7.10
    container_name: ziti-host
    volumes:
      - ${IDENTITY_PATH:-/root/web-host.json}:/etc/ziti/web-host.json:ro
    extra_hosts:
      - "quickstart:${CTRL_IP}"
    restart: always
    networks: [ ziti-net ]

networks:
  ziti-net: { driver: bridge }
```

## Grav 연동 패턴
- **컨테이너 간 통신**: 주소 `grav:80` 노출
- **호스트 루프백**: 호스트의 `127.0.0.1:80` 노출

## OpenZiti 서비스/정책 예시
### 컨테이너 간 통신(권장)
```bash
ziti edge create config web-host host.v1  '{"protocol":"tcp","address":"grav","port":80}'
ziti edge create config web-intc intercept.v1 '{"addresses":["portal.ziti"],"portRanges":[{"low":80,"high":80}],"protocols":["tcp"]}'
ziti edge create service web-portal --configs web-host,web-intc
ziti edge create service-policy web-portal-bind Bind --service-roles @web-portal --identity-roles @newweb-host
ziti edge create service-policy web-portal-dial Dial --service-roles @web-portal --identity-roles @desktop-client
```
### 호스트 루프백 대안
```bash
ziti edge create config web-host host.v1  '{"protocol":"tcp","address":"127.0.0.1","port":80}'
ziti edge create config web-intc intercept.v1 '{"addresses":["portal.ziti"],"portRanges":[{"low":80,"high":80}],"protocols":["tcp"]}'
```

## Kubernetes 배포 예시
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: ziti-identity
type: Opaque
data:
  web-host.json: REPLACE_WITH_BASE64
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ziti-host
spec:
  replicas: 1
  selector: { matchLabels: { app: ziti-host } }
  template:
    metadata: { labels: { app: ziti-host } }
    spec:
      hostAliases:
        - ip: "192.168.56.105"
          hostnames: ["quickstart"]
      containers:
        - name: ziti-host
          image: ghcr.io/OWNER/ziti-host:1.7.10
          volumeMounts:
            - name: id
              mountPath: /etc/ziti
              readOnly: true
          readinessProbe:
            exec: { command: ["/usr/local/bin/ziti-edge-tunnel","tunnel_status"] }
            initialDelaySeconds: 5
            periodSeconds: 15
      volumes:
        - name: id
          secret:
            secretName: ziti-identity
            items:
              - key: web-host.json
                path: web-host.json
```
검증:
```bash
kubectl create secret generic ziti-identity   --from-file=web-host.json=/root/web-host.json -n default   --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f k8s/ziti-host.yaml --dry-run=client
```

## 운영 & 관찰성
```bash
docker logs -f ziti-host
docker exec -it ziti-host /usr/local/bin/ziti-edge-tunnel tunnel_status
docker exec -it ziti-host /usr/local/bin/ziti-edge-tunnel set_log_level debug
```

## 트러블슈팅
- **CONTROLLER_UNAVAILABLE / unknown node or service**
  - `extra_hosts`의 `quickstart:${CTRL_IP}` 확인, `curl -k https://$CTRL_IP:1280/edge/client/v1/version`
- **resource busy or locked**
  - 엔트리포인트가 `/run/ziti` 사본을 사용 → 최신 이미지 사용
- **local 'ziti' group not found**
  - 경고 수준. 소켓 권한용 그룹을 엔트리포인트에서 생성
- **시간 오차**
  - NTP 동기화

## 보안 수칙
- 절대 커밋 금지: `*.jwt`, `web-host.json`, 키/인증서
- 권한 최소화: `chmod 600 /root/web-host.json`
- 레지스트리 토큰/시크릿은 Secret/환경변수로만 전달

## CI/CD (선택)
GitHub Actions로 GHCR 푸시:
```yaml
name: build-and-push
on:
  push:
    branches: [ "main" ]
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

## 버전/호환성/성능
- Ziti Controller v1.5.x + Edge Tunnel v1.7.x 조합 검증.  
- 최소 1 vCPU / 256MiB, 권장 2 vCPU / 512MiB+.

## 알려진 제한/주의사항
- 컨트롤러 인증서 이름 불일치 시 TLS 실패 → `quickstart` DNS/hosts 매핑 필요.
- JWT 재사용 불가.

## 부록
### base64 팁
```bash
base64 -w0 /root/web-host.json
```
### 인증서/연결 확인
```bash
openssl s_client -connect $CTRL_IP:1280 -servername quickstart -tls1_2 </dev/null | openssl x509 -noout -subject -issuer
curl -k https://$CTRL_IP:1280/edge/client/v1/version
```
