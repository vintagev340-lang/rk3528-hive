BINARY  = hive-registry
GOOS   ?= linux
GOARCH ?= amd64

.PHONY: build tidy clean

build: tidy
	CGO_ENABLED=0 GOOS=$(GOOS) GOARCH=$(GOARCH) \
	  go build -ldflags="-s -w" -o $(BINARY) .

# 交叉编译为 arm64（如果管理服务器是 ARM）
build-arm64:
	CGO_ENABLED=0 GOOS=linux GOARCH=arm64 \
	  go build -ldflags="-s -w" -o $(BINARY)-arm64 .

tidy:
	go mod tidy

clean:
	rm -f $(BINARY) $(BINARY)-arm64
