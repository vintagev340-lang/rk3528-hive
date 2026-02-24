#!/bin/bash
# Armbian 构建钩子 - 在 chroot 内执行
# 此时 overlay/ 目录的文件已被复制到镜像根目录
set -e

echo ">>> Running customize-image.sh for RK3528A edge node..."

# ===== 系统基础配置 =====
# 开启 IP 转发
cat >> /etc/sysctl.d/99-edge.conf << 'EOF'
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
net.core.rmem_max=67108864
net.core.wmem_max=67108864
EOF

# ===== 服务管理 =====
# （软件安装后在此 enable 服务，目前留空待后续添加）
# systemctl enable mihomo
# systemctl enable frpc
# systemctl enable provision-node

# ===== 镜像清洗（移除唯一标识，供批量烧录）=====
/usr/local/bin/sanitize-node.sh || true

echo ">>> customize-image.sh done."
