package main

import (
	"log"
	"net/http"
	"os"
)

// Node 是所有接口通用的节点数据结构。
// 与数据库列一一对应，JSON tag 为接口规范。
type Node struct {
	MAC          string `json:"mac"`
	MAC6         string `json:"mac6"`
	Hostname     string `json:"hostname"`
	CFURL        string `json:"cf_url"`
	TunnelID     string `json:"tunnel_id"`
	TailscaleIP  string `json:"tailscale_ip"`
	EasytierIP   string `json:"easytier_ip"`
	FRPPort      int    `json:"frp_port"`
	XrayUUID     string `json:"xray_uuid"`
	Location     string `json:"location"`
	Note         string `json:"note"`
	RegisteredAt string `json:"registered_at"`
	LastSeen     string `json:"last_seen"`
}

// SELECT 列顺序，与 scanNode / scanNodeRow 的 Scan 参数严格对应
const nodeCols = "mac, mac6, hostname, cf_url, tunnel_id, tailscale_ip, easytier_ip, frp_port, xray_uuid, location, note, registered_at, last_seen"

var xrayPath = getenv("XRAY_PATH", "ray") // xray path，默认 /ray

func main() {
	initDB()

	mux := http.NewServeMux()

	// ── 节点注册（设备端调用，无认证）────────────────────────────────────
	mux.HandleFunc("POST /api/nodes/register", handleRegister)

	// ── 节点查询（无认证）────────────────────────────────────────────────
	mux.HandleFunc("GET /api/nodes", handleListNodes)
	mux.HandleFunc("GET /api/nodes/{mac}", handleGetNode)

	// ── 节点管理（需要 Authorization: Bearer <API_SECRET>）──────────────
	mux.HandleFunc("PATCH /api/nodes/{mac}", handleUpdateNode)
	mux.HandleFunc("DELETE /api/nodes/{mac}", handleDeleteNode)

	// ── 订阅（无认证）────────────────────────────────────────────────────
	mux.HandleFunc("GET /api/subscription", handleSubscriptionVless)
	mux.HandleFunc("GET /api/subscription/clash", handleSubscriptionClash)

	// ── 运维接口（无认证）────────────────────────────────────────────────
	mux.HandleFunc("GET /api/prometheus-targets", handlePrometheusTargets)
	mux.HandleFunc("GET /api/labels", handleLabels)
	mux.HandleFunc("GET /health", handleHealth)

	// ── 控制台 Dashboard ─────────────────────────────────────────────────
	mux.HandleFunc("GET /", handleIndex)

	addr := getenv("LISTEN_ADDR", ":8080")
	log.Printf("hive-registry listening on %s", addr)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatal(err)
	}
}

// getenv 返回环境变量值，未设置时返回默认值
func getenv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
