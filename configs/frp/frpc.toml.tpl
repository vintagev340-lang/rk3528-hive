# FRP 客户端配置模板
# 由 scripts/build.sh 通过 envsubst 渲染，勿直接编辑渲染后的文件

serverAddr = "${FRP_SERVER_ADDR}"
serverPort = ${FRP_SERVER_PORT}

auth.method = "token"
auth.token = "${FRP_AUTH_TOKEN}"

transport.tcpMux = true

# remotePort 由首次启动脚本根据 MAC 地址哈希动态计算后替换 REMOTE_PORT_PLACEHOLDER
[[proxies]]
name = "ssh-HOSTNAME_PLACEHOLDER"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = REMOTE_PORT_PLACEHOLDER
