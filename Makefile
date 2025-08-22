.PHONY: fetch build run up logs stop clean

TAG ?= 1.7.10
BIN := bin/ziti-edge-tunnel

fetch:
	@mkdir -p bin
	@test -n "$(URL)" || (echo "Set URL=... to download ziti-edge-tunnel"; exit 1)
	curl -L "$(URL)" -o $(BIN)
	chmod +x $(BIN)

build:
	@test -f $(BIN) || (echo "Missing $(BIN). Put ziti-edge-tunnel in ./bin/ or run: make fetch URL=..."; exit 1)
	docker build -t ziti-host:$(TAG) .

run:
	@test -n "$$CTRL_IP" || (echo "export CTRL_IP=<controller_ip>"; exit 1)
	@test -n "$$IDENTITY_PATH" || (echo "export IDENTITY_PATH=/root/web-host.json"; exit 1)
	docker run -d --name ziti-host \
	  --add-host quickstart:$$CTRL_IP \
	  -v $$IDENTITY_PATH:/etc/ziti/web-host.json \
	  --restart always \
	  ziti-host:$(TAG)

up:
	@test -f .env || (cp .env.example .env && echo "Created .env from example. Edit CTRL_IP/IDENTITY_PATH"; )
	docker compose up -d

logs:
	docker logs -f ziti-host

stop:
	docker rm -f ziti-host || true

clean: stop
	docker rmi ziti-host:$(TAG) || true
