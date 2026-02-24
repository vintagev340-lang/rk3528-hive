#!/usr/bin/env python3
"""
Edge Node Registry API
- POST /api/nodes/register      — 设备首次启动时上报
- GET  /api/nodes               — 列出所有节点
- PATCH /api/nodes/{mac}        — 管理员更新节点备注（地理位置等）
- GET  /api/subscription        — 生成 v2ray 订阅链接（VLESS+WS+TLS）
- GET  /api/prometheus-targets  — Prometheus file_sd 格式，供 cron 更新
- GET  /api/labels              — 可打印的设备标签 HTML 页
"""

from fastapi import FastAPI, HTTPException
from fastapi.responses import Response, HTMLResponse
from pydantic import BaseModel
import sqlite3
import base64
import os
from datetime import datetime
from contextlib import contextmanager
from typing import Optional

app = FastAPI(title="Edge Node Registry", version="1.0")

DB_PATH   = os.environ.get("DB_PATH",   "/data/registry.db")
XRAY_PATH = os.environ.get("XRAY_PATH", "ray")   # CF Tunnel 上的 WS 路径


# ─────────────────────────────────────────────────────────
# 数据库
# ─────────────────────────────────────────────────────────

@contextmanager
def get_db():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


@app.on_event("startup")
def init_db():
    with get_db() as conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS nodes (
                mac           TEXT PRIMARY KEY,
                mac6          TEXT NOT NULL,
                hostname      TEXT NOT NULL,
                cf_url        TEXT NOT NULL,
                tailscale_ip  TEXT DEFAULT 'pending',
                xray_uuid     TEXT NOT NULL,
                frp_port      INTEGER DEFAULT 0,
                location      TEXT DEFAULT '',
                registered_at TEXT NOT NULL,
                last_seen     TEXT NOT NULL
            )
        """)


# ─────────────────────────────────────────────────────────
# 数据模型
# ─────────────────────────────────────────────────────────

class NodeRegister(BaseModel):
    mac:          str
    mac6:         str
    hostname:     str
    cf_url:       str
    tailscale_ip: Optional[str] = "pending"
    xray_uuid:    str
    frp_port:     Optional[int] = 0

class NodeUpdate(BaseModel):
    location:     Optional[str] = None
    tailscale_ip: Optional[str] = None


# ─────────────────────────────────────────────────────────
# 接口
# ─────────────────────────────────────────────────────────

@app.post("/api/nodes/register", summary="设备注册（首次启动调用）")
def register_node(node: NodeRegister):
    now = datetime.utcnow().isoformat()
    with get_db() as conn:
        existing = conn.execute(
            "SELECT registered_at FROM nodes WHERE mac=?", (node.mac,)
        ).fetchone()
        registered_at = existing["registered_at"] if existing else now

        conn.execute("""
            INSERT OR REPLACE INTO nodes
            (mac, mac6, hostname, cf_url, tailscale_ip, xray_uuid,
             frp_port, location, registered_at, last_seen)
            VALUES (?, ?, ?, ?, ?, ?, ?, COALESCE(
                (SELECT location FROM nodes WHERE mac=?), ''
            ), ?, ?)
        """, (
            node.mac, node.mac6, node.hostname, node.cf_url,
            node.tailscale_ip, node.xray_uuid, node.frp_port,
            node.mac, registered_at, now
        ))

    return {"status": "ok", "hostname": node.hostname, "registered_at": registered_at}


@app.get("/api/nodes", summary="列出所有节点")
def list_nodes():
    with get_db() as conn:
        rows = conn.execute(
            "SELECT * FROM nodes ORDER BY registered_at"
        ).fetchall()
    return [dict(r) for r in rows]


@app.patch("/api/nodes/{mac}", summary="更新节点信息（管理员用）")
def update_node(mac: str, data: NodeUpdate):
    fields, values = [], []
    if data.location is not None:
        fields.append("location=?")
        values.append(data.location)
    if data.tailscale_ip is not None:
        fields.append("tailscale_ip=?")
        values.append(data.tailscale_ip)
    if not fields:
        raise HTTPException(status_code=400, detail="No fields to update")

    values.append(mac)
    with get_db() as conn:
        result = conn.execute(
            f"UPDATE nodes SET {', '.join(fields)} WHERE mac=?", values
        )
        if result.rowcount == 0:
            raise HTTPException(status_code=404, detail="Node not found")
    return {"status": "ok"}


@app.get("/api/subscription", summary="生成 v2ray 订阅链接")
def get_subscription():
    """
    返回 Base64 编码的订阅内容，包含所有节点的 VLESS URL。

    客户端配置说明：
      协议: VLESS
      地址: edge-<mac6>.yourdomain.com  （CF Tunnel 域名）
      端口: 443
      传输: WebSocket, path=/<XRAY_PATH>
      TLS:  开启, SNI = 同上域名
      UUID: 每台节点独立
    """
    with get_db() as conn:
        rows = conn.execute(
            "SELECT * FROM nodes ORDER BY hostname"
        ).fetchall()

    links = []
    for row in rows:
        host = row["cf_url"]
        uuid = row["xray_uuid"]
        name = row["location"] or row["hostname"]
        path = XRAY_PATH.lstrip("/")
        link = (
            f"vless://{uuid}@{host}:443"
            f"?encryption=none&security=tls&sni={host}"
            f"&type=ws&host={host}&path=%2F{path}"
            f"#{name}"
        )
        links.append(link)

    encoded = base64.b64encode("\n".join(links).encode()).decode()
    return Response(content=encoded, media_type="text/plain")


@app.get("/api/prometheus-targets", summary="Prometheus file_sd 格式")
def prometheus_targets():
    """
    由 cron 每分钟调用，写入 /etc/prometheus/targets/nodes.json。
    Prometheus 通过 file_sd_configs 自动加载。
    """
    with get_db() as conn:
        rows = conn.execute(
            "SELECT * FROM nodes WHERE tailscale_ip != 'pending' AND tailscale_ip IS NOT NULL"
        ).fetchall()

    targets = []
    for row in rows:
        targets.append({
            "targets": [f"{row['tailscale_ip']}:9100"],
            "labels": {
                "instance":  row["hostname"],
                "cf_url":    row["cf_url"],
                "location":  row["location"] or "",
                "mac6":      row["mac6"],
            }
        })
    return targets


@app.get("/api/labels", response_class=HTMLResponse, summary="可打印设备标签")
def printable_labels():
    """A4 纸打印，每行 4 个，浏览器 Ctrl+P 直接打印。"""
    with get_db() as conn:
        rows = conn.execute(
            "SELECT * FROM nodes ORDER BY registered_at"
        ).fetchall()

    cards = ""
    for i, row in enumerate(rows, 1):
        cards += f"""
        <div class="card">
            <div class="num">#{i:03d}</div>
            <div class="id">{row['mac6']}</div>
            <div class="url">{row['cf_url']}</div>
            <div class="loc">{row['location'] or '—'}</div>
            <div class="ts">{row['registered_at'][:10]}</div>
        </div>"""

    return f"""<!DOCTYPE html>
<html><head>
<meta charset="utf-8">
<title>Edge Node Labels</title>
<style>
  * {{ box-sizing: border-box; margin: 0; padding: 0; }}
  body {{ font-family: 'Courier New', monospace; background: #fff; }}
  .grid {{ display: grid; grid-template-columns: repeat(4, 1fr); gap: 6px; padding: 12px; }}
  .card {{
    border: 1.5px solid #222;
    padding: 8px;
    text-align: center;
    page-break-inside: avoid;
    min-height: 90px;
  }}
  .num  {{ font-size: 26px; font-weight: bold; color: #111; }}
  .id   {{ font-size: 15px; color: #444; letter-spacing: 2px; margin: 2px 0; }}
  .url  {{ font-size: 9px; color: #555; word-break: break-all; margin: 3px 0; }}
  .loc  {{ font-size: 11px; color: #333; font-style: italic; }}
  .ts   {{ font-size: 8px; color: #999; margin-top: 2px; }}
  @media print {{
    .grid {{ gap: 4px; padding: 8px; }}
    .card {{ border: 1px solid black; }}
  }}
</style>
</head>
<body>
<div class="grid">{cards}</div>
</body></html>"""


@app.get("/", response_class=HTMLResponse, summary="控制台首页")
def index():
    with get_db() as conn:
        total = conn.execute("SELECT COUNT(*) FROM nodes").fetchone()[0]
        online = conn.execute(
            "SELECT COUNT(*) FROM nodes WHERE tailscale_ip != 'pending'"
        ).fetchone()[0]
    return f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Node Registry</title>
<style>body{{font-family:monospace;padding:20px;}} a{{margin-right:16px;}}</style>
</head><body>
<h2>Edge Node Registry</h2>
<p>Total: <strong>{total}</strong> | Online (Tailscale): <strong>{online}</strong></p>
<hr>
<a href="/api/nodes">All Nodes (JSON)</a>
<a href="/api/subscription">Subscription Link</a>
<a href="/api/labels">Print Labels</a>
<a href="/docs">API Docs</a>
</body></html>"""
