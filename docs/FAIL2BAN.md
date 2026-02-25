# Hive Network fail2ban 入侵防护配置

本文档介绍 Hive Network 节点的 fail2ban 入侵检测和防护配置。

## 🛡️ fail2ban 概述

fail2ban 是一个入侵防护系统，通过监控日志文件来检测恶意行为并自动封禁攻击者 IP。

### 主要功能

- **SSH 暴力破解防护**：自动封禁多次 SSH 登录失败的 IP
- **端口扫描检测**：检测并阻止端口扫描行为
- **系统服务保护**：保护 sudo、系统认证等服务
- **与 UFW 集成**：自动添加/移除防火墙规则
- **白名单保护**：确保信任网络不被误封

## 📂 相关文件

```
/usr/local/bin/setup-fail2ban.sh           # fail2ban 初始化脚本
/usr/local/bin/hive-fail2ban                # fail2ban 管理工具
/etc/systemd/system/hive-fail2ban.service  # 系统服务配置
/etc/fail2ban/jail.d/hive-*.conf           # Hive 自定义监狱配置
/etc/fail2ban/filter.d/hive-*.conf         # Hive 自定义过滤器
/var/lib/hive/fail2ban-configured          # 配置完成标记文件
```

## 🚫 保护策略

### SSH 保护

| 监狱 | 最大重试 | 封禁时间 | 查找时间 | 说明 |
|------|----------|----------|----------|------|
| sshd | 3 次 | 2 小时 | 10 分钟 | 标准 SSH 保护 |
| sshd-aggressive | 2 次 | 24 小时 | 5 分钟 | 严格模式 |

### 系统服务保护

| 监狱 | 最大重试 | 封禁时间 | 保护目标 |
|------|----------|----------|----------|
| systemd-login | 5 次 | 1 小时 | 系统登录 |
| sudo-auth | 3 次 | 1 小时 | sudo 认证 |
| systemd-auth | 5 次 | 30 分钟 | 系统认证 |

### 网络安全

| 监狱 | 最大重试 | 封禁时间 | 检测内容 |
|------|----------|----------|----------|
| hive-portscan | 10 次 | 1 小时 | 端口扫描 |

### 白名单网络

以下网络不会被 fail2ban 封禁：
- `127.0.0.1/8` - 本地回环
- `192.168.0.0/16` - 本地网络
- `10.0.0.0/8` - 私有网络
- `172.16.0.0/12` - 私有网络
- `100.0.0.0/8` - Tailscale 网络

## 🛠️ fail2ban 管理

### 查看状态

```bash
# 查看整体状态
hive-fail2ban status

# 查看所有监狱状态
hive-fail2ban jails

# 查看被封禁的 IP
hive-fail2ban banned
```

### IP 管理

```bash
# 解封特定 IP
sudo hive-fail2ban unban 203.0.113.100

# 查看 fail2ban 日志
hive-fail2ban logs

# 实时监控日志
sudo tail -f /var/log/fail2ban.log
```

### 配置管理

```bash
# 测试配置
sudo hive-fail2ban test

# 重新加载配置
sudo hive-fail2ban reload

# 检查服务状态
sudo systemctl status fail2ban
```

## 🔧 高级配置

### 修改封禁策略

编辑相应的配置文件：

```bash
# SSH 保护设置
sudo nano /etc/fail2ban/jail.d/hive-ssh.conf

# 系统服务保护
sudo nano /etc/fail2ban/jail.d/hive-services.conf

# 端口扫描检测
sudo nano /etc/fail2ban/jail.d/hive-suspicious.conf
```

### 自定义白名单

编辑基础配置：

```bash
sudo nano /etc/fail2ban/jail.d/hive-defaults.conf
```

添加信任的 IP 或网段到 `ignoreip` 列表：

```ini
[DEFAULT]
ignoreip = 127.0.0.1/8
           ::1
           192.168.0.0/16
           10.0.0.0/8
           172.16.0.0/12
           100.0.0.0/8
           YOUR_OFFICE_IP/32
```

### 邮件通知

如需启用邮件通知，编辑默认配置：

```bash
sudo nano /etc/fail2ban/jail.d/hive-defaults.conf
```

取消注释并配置邮件设置：

```ini
[DEFAULT]
destemail = admin@yourdomain.com
sender = fail2ban@hive-node
mta = sendmail
action = %(action_mw)s
```

## 🔍 日志监控

### 实时监控

```bash
# 监控 fail2ban 活动
sudo tail -f /var/log/fail2ban.log

# 监控特定监狱
sudo fail2ban-client tail sshd

# 监控系统认证日志
sudo journalctl -f -u ssh
```

### 日志分析

```bash
# 查看最近封禁记录
sudo grep "Ban " /var/log/fail2ban.log | tail -10

# 查看解封记录
sudo grep "Unban " /var/log/fail2ban.log | tail -10

# 统计攻击源
sudo grep "Ban " /var/log/fail2ban.log | awk '{print $8}' | sort | uniq -c | sort -nr
```

## ⚠️ 安全注意事项

### 1. 避免自我封锁

确保管理 IP 在白名单中：

```bash
# 添加当前 IP 到白名单
current_ip=$(curl -s ifconfig.me)
sudo nano /etc/fail2ban/jail.d/hive-defaults.conf
# 在 ignoreip 中添加 $current_ip
```

### 2. 紧急解封

如果被误封，可通过以下方式解封：

1. **物理控制台访问**：
   ```bash
   sudo hive-fail2ban unban YOUR_IP
   ```

2. **通过其他管理通道**：
   - Tailscale: `ssh root@hive-a4b2c1`
   - FRP: `ssh -p 12345 root@your-vps`

3. **临时禁用 fail2ban**：
   ```bash
   sudo systemctl stop fail2ban
   ```

### 3. 配置测试

修改配置后务必测试：

```bash
# 测试配置语法
sudo hive-fail2ban test

# 重新加载配置
sudo hive-fail2ban reload
```

### 4. 日志轮转

fail2ban 日志已配置自动轮转：
- 保留 30 天
- 每日轮转
- 自动压缩

## 🆘 故障排除

### fail2ban 无法启动

1. **检查配置语法**：
   ```bash
   sudo fail2ban-client --test
   ```

2. **检查依赖服务**：
   ```bash
   sudo systemctl status ufw
   sudo systemctl status rsyslog
   ```

3. **查看详细错误**：
   ```bash
   sudo journalctl -u fail2ban -f
   ```

### 监狱无法启动

1. **检查日志文件**：
   ```bash
   # 确保日志文件存在且可读
   ls -la /var/log/auth.log
   ls -la /var/log/kern.log
   ```

2. **检查过滤器**：
   ```bash
   sudo fail2ban-regex /var/log/auth.log /etc/fail2ban/filter.d/sshd.conf
   ```

### 误封问题

1. **检查白名单**：
   ```bash
   sudo fail2ban-client get sshd ignoreip
   ```

2. **查看封禁原因**：
   ```bash
   sudo grep "YOUR_IP" /var/log/fail2ban.log
   ```

3. **立即解封**：
   ```bash
   sudo hive-fail2ban unban YOUR_IP
   ```

## 📊 性能影响

fail2ban 对系统性能影响极小：
- **CPU 使用**：< 1%
- **内存使用**：~10-20MB
- **磁盘 I/O**：仅日志读取
- **网络影响**：无

## 📚 相关资源

- [fail2ban 官方文档](https://www.fail2ban.org/wiki/index.php/Manual)
- [fail2ban 配置示例](https://github.com/fail2ban/fail2ban/tree/master/config)
- [UFW 与 fail2ban 集成](https://help.ubuntu.com/community/Fail2ban)

---

**注意**：fail2ban 配置涉及网络安全，修改前请确保理解各项设置的含义，并做好白名单和应急访问预案。