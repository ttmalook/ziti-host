한번에 건설하는 OpenZiti Quickstart (Docker Compose)

# 프로세스 확인 : ps aux | grep git

1. 환경설정 (Ubuntu)
 1-1  sudo apt update && sudo apt upgrade -y
	sudo apt install -y git curl unzip
 1-2 sudo vi /etc/systemd/resolved.conf
      # 아래 항목 추가 또는 수정
	DNS=8.8.8.8
	FallbackDNS=1.1.1.1
      # 적용
	sudo systemctl restart systemd-resolved


2. Docker / Docker Compose 설치

 2-1	# Docker
	curl -fsSL https://get.docker.com -o get-docker.sh
	sudo sh get-docker.sh

 2-2	# Docker Compose
	sudo curl -L "https://github.com/docker/compose/releases/download/v2.24.5/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
	sudo chmod +x /usr/local/bin/docker-compose

3. GitHub 바이 OpenZiti 소스 클론

 3-1 # curl -L https://github.com/openziti/ziti/archive/refs/heads/main.zip -o ziti.zip
	 unzip ziti.zip
	 cd ziti-main/quickstart/docker/all-in-one
	 sudo docker-compose up -d

 3-2 # Docker 컨테이너 정상 실행 여부 확인
	sudo docker ps
        예시)
	root@client:~/ziti-main/quickstart/docker/all-in-one# sudo docker ps
	CONTAINER ID   IMAGE                             COMMAND                  CREATED          STATUS                    PORTS                                            NAMES
	042fcb35865d   openziti/ziti-controller:latest   "bash -euc 'ZITI_CMD…"   36 minutes ago   Up 36 minutes (healthy)   0.0.0.0:1280->1280/tcp, 0.0.0.0:3022->3022/tcp   all-in-one-quickstart-1

4. Ziti Console UI 접속

 4-1 # 브라우저에서 VM IP 또는 호스트 포트 포워딩 기준으로 접속 시도:
	https://<VM_IP>:1280/zac
	→ 로그인 기본값:
	    ID: admin
	    PW: admin

5. hosts 파일 수정
	/etc/hosts
	→hosts에 추가 
	   192.168.56.105  quickstart
