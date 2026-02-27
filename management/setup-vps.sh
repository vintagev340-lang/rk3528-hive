#!/bin/bash
# VPS 管理端一键安装脚本（Ubuntu 22.04 / 24.04 / Debian trixie）
# 安装：hive-registry、Docker、Ansible、部署 Prometheus+Grafana
# 幂等：可重复执行，已安装的组件只会更新配置或重启服务
#
# 在 VPS 上执行：
#   git clone <your-repo> /opt/rk3528-hive
#   cd /opt/rk3528-hive
#   cp .env.example .env && nano .env    # 填入所有必填项
#   bash management/setup-vps.sh

set -e
cd "$(dirname "$0")/.."
ROOT_DIR="$(pwd)"

# 加载 .env
if [ -f "${ROOT_DIR}/.env" ]; then
    set -a; source "${ROOT_DIR}/.env"; set +a
else
    echo "!!! .env not found. Copy .env.example and fill in the values first."
    exit 1
fi

echo "=== Hive Management Setup ==="

# ─────────────────────────────────────────────
# 1. 安装 Docker
# ─────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
    echo ">>> Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
else
    echo ">>> Docker already installed: $(docker --version)"
fi

# ─────────────────────────────────────────────
# 2. 安装 Ansible + community.general
# ─────────────────────────────────────────────
if ! command -v ansible &>/dev/null; then
    echo ">>> Installing Ansible..."
    apt-get update -q
    apt-get install -y software-properties-common
    # Ubuntu 专属 PPA；Debian 直接用系统源
    if grep -qi ubuntu /etc/os-release; then
        add-apt-repository --yes --update ppa:ansible/ansible
    else
        apt-get update -q
    fi
    apt-get install -y ansible
else
    echo ">>> Ansible already installed: $(ansible --version | head -1)"
fi

if ! ansible-galaxy collection list community.general &>/dev/null; then
    echo ">>> Installing Ansible collections..."
    ansible-galaxy collection install community.general --upgrade
fi

# ─────────────────────────────────────────────
# 3. 安装依赖工具
# ─────────────────────────────────────────────
apt-get install -y --no-install-recommends jq curl

# ─────────────────────────────────────────────
# 4. 安装 hive-registry（Go 单二进制）
# ─────────────────────────────────────────────
echo ">>> Installing hive-registry..."

REGISTRY_BIN="${ROOT_DIR}/management/registry/hive-registry"
if [ ! -f "${REGISTRY_BIN}" ]; then
    echo "!!! Binary not found at ${REGISTRY_BIN}"
    echo "    Run 'make build' (or 'make build-arm64') in management/registry/ first."
    exit 1
fi

cp "${REGISTRY_BIN}" /usr/local/bin/hive-registry
chmod +x /usr/local/bin/hive-registry

# 写入 EnvironmentFile（每次执行都刷新，确保密码等变量同步）
cat > /etc/hive-registry.env << EOF
LISTEN_ADDR=${REGISTRY_LISTEN_ADDR:-127.0.0.1:8080}
MYSQL_HOST=${REGISTRY_MYSQL_HOST:-127.0.0.1}
MYSQL_PORT=${REGISTRY_MYSQL_PORT:-3306}
MYSQL_USER=${REGISTRY_MYSQL_USER:-hive}
MYSQL_PASSWORD=${REGISTRY_MYSQL_PASSWORD}
MYSQL_DB=${REGISTRY_MYSQL_DB:-hive_registry}
DB_MAX_OPEN=${REGISTRY_DB_MAX_OPEN:-10}
DB_MAX_IDLE=${REGISTRY_DB_MAX_IDLE:-3}
XRAY_PATH=${REGISTRY_XRAY_PATH:-ray}
API_SECRET=${REGISTRY_API_SECRET}
EOF
chmod 600 /etc/hive-registry.env

# 安装或更新 systemd 服务单元
cat > /etc/systemd/system/hive-registry.service << 'UNIT'
[Unit]
Description=Hive Node Registry
After=network.target mysql.service
Wants=mysql.service

[Service]
Type=simple
User=nobody
EnvironmentFile=/etc/hive-registry.env
ExecStart=/usr/local/bin/hive-registry
Restart=always
RestartSec=5
MemoryMax=64M
CPUQuota=20%

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable hive-registry
# 无论服务状态如何，重启以加载最新二进制和配置
systemctl restart hive-registry
echo ">>> hive-registry: $(systemctl is-active hive-registry)"

# ─────────────────────────────────────────────
# 5. 创建运行时目录
# ─────────────────────────────────────────────
mkdir -p "${ROOT_DIR}/management/prometheus/targets"
# 只在文件不存在时初始化，避免覆盖已有数据
[ -f "${ROOT_DIR}/management/prometheus/targets/nodes.json" ] || \
    echo "[]" > "${ROOT_DIR}/management/prometheus/targets/nodes.json"

# ─────────────────────────────────────────────
# 6. 启动 Prometheus + Grafana
# ─────────────────────────────────────────────
echo ">>> Starting Prometheus + Grafana..."
cd "${ROOT_DIR}/management"
docker compose up -d --remove-orphans
cd "${ROOT_DIR}"

# ─────────────────────────────────────────────
# 7. cron：每分钟从 hive-registry 刷新 Prometheus 节点列表
# ─────────────────────────────────────────────
REGISTRY_LOCAL_URL="http://${REGISTRY_LISTEN_ADDR:-127.0.0.1:8080}"
TARGETS_FILE="${ROOT_DIR}/management/prometheus/targets/nodes.json"
AUTH_HEADER=""
if [ -n "${REGISTRY_API_SECRET}" ]; then
    AUTH_HEADER="-H \"Authorization: Bearer ${REGISTRY_API_SECRET}\""
fi

CRON_LINE="* * * * * root curl -sf ${AUTH_HEADER} ${REGISTRY_LOCAL_URL}/api/prometheus-targets > ${TARGETS_FILE}"
# 替换同名 cron 行（grep 匹配 prometheus-targets，保证幂等）
TMP=$(mktemp)
(crontab -l 2>/dev/null | grep -v "prometheus-targets"; echo "$CRON_LINE") > "$TMP"
crontab "$TMP"
rm -f "$TMP"
echo ">>> Cron installed: prometheus-targets refresh every minute"

echo ""
echo "=== Setup Complete ==="
echo ""
echo "  hive-registry  : ${REGISTRY_LOCAL_URL}  (local only)"
echo "  Prometheus     : ${PROMETHEUS_EXTERNAL_URL:-http://localhost:4230/prometheus/}"
echo "  Grafana        : ${GRAFANA_ROOT_URL:-http://localhost:4231/grafana}"
echo "  Grafana PW     : ${GRAFANA_PASSWORD:-changeme}"
echo ""
echo "  Verify registry:"
if [ -n "${REGISTRY_API_SECRET}" ]; then
    echo "    curl -H 'Authorization: Bearer ${REGISTRY_API_SECRET}' ${REGISTRY_LOCAL_URL}/health"
    echo "    curl -H 'Authorization: Bearer ${REGISTRY_API_SECRET}' ${REGISTRY_LOCAL_URL}/api/nodes"
else
    echo "    curl ${REGISTRY_LOCAL_URL}/health"
    echo "    curl ${REGISTRY_LOCAL_URL}/api/nodes"
fi
echo ""
echo "  If no nginx reverse proxy, SSH tunnel to access locally:"
echo "    ssh -L 4230:localhost:4230 -L 4231:localhost:4231 root@<VPS-IP>"
echo "    Then open: http://localhost:4231"
echo ""
echo "  Grafana setup:"
echo "    1. Login admin / (password above)"
echo "    2. Dashboards -> Import -> ID: 1860  (Node Exporter Full)"
echo "    3. Select 'Prometheus' datasource -> Import"
echo ""
echo "  Ansible test (after nodes are up):"
echo "    cd ${ROOT_DIR}"
echo "    ansible-playbook ansible/playbooks/ping.yml"
echo ""
