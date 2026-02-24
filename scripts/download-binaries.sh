#!/bin/bash
# 下载预编译 arm64 二进制到 overlay 目录
# 版本号在此统一管理
set -e

MIHOMO_VER="v1.19.2"
FRP_VER="0.61.1"
EASYTIER_VER="v2.1.3"

DEST="armbian-build/userpatches/overlay/usr/local/bin"

echo ">>> Downloading mihomo ${MIHOMO_VER}..."
curl -L "https://github.com/MetaCubeX/mihomo/releases/download/${MIHOMO_VER}/mihomo-linux-arm64-${MIHOMO_VER}.gz" \
    | gunzip > "${DEST}/mihomo"
chmod +x "${DEST}/mihomo"

echo ">>> Downloading frpc ${FRP_VER}..."
curl -L "https://github.com/fatedier/frp/releases/download/v${FRP_VER}/frp_${FRP_VER}_linux_arm64.tar.gz" \
    | tar xz --strip-components=1 -C "${DEST}" "frp_${FRP_VER}_linux_arm64/frpc"
chmod +x "${DEST}/frpc"

echo ">>> Downloading easytier ${EASYTIER_VER}..."
curl -L "https://github.com/EasyTier/EasyTier/releases/download/${EASYTIER_VER}/easytier-linux-aarch64-${EASYTIER_VER}.zip" \
    -o /tmp/easytier.zip
unzip -jo /tmp/easytier.zip "*/easytier-core" -d "${DEST}"
chmod +x "${DEST}/easytier-core"
rm /tmp/easytier.zip

echo ">>> All binaries downloaded."
ls -lh "${DEST}"
