# 个人 VPS 管理辅助工具

使用官方 Tailscale，无需编译本仓库。仅新增外围 PowerShell 工具，不安装服务、不更改防火墙、服务器或 Tailscale 配置。兼容 Windows PowerShell 5.1，无第三方依赖。

## 状态与 WindTerm

安装并登录官方 Tailscale，确保 `tailscale` 命令可用。在本目录打开 PowerShell：

```powershell
.\ts-status.ps1
```

每个在线节点进行一次最多等待 3 秒的 Tailscale ping，显示在线状态、Direct / DERP / PeerRelay 和本次 RTT。离线节点不探测；失败或未知输出显示 Unknown。首包可能经过 DERP，不能据此认定长期无法直连。Online 仅表示控制面在线；RTT 不是 SSH、HY2 或应用延迟。工具不使用状态 JSON 中的归属 DERP 区域推断实际路径。

WindTerm 的 Host 填输出的 `WindTermHost`，端口 22，继续使用原有 SSH 用户及密钥。MagicDNS 需在客户端可解析；否则使用 Address。脚本不修改 WindTerm 会话。

## 检查管理端口

将真实节点清单保存在**仓库外**，例如 `$env:USERPROFILE\tailscale-nodes.csv`。CSV 内容格式如下（均为文档示例地址，运行前替换；只检查自己拥有或获准检查的主机）：

```csv
Name,TailnetIP,PublicIP
server-example,100.64.0.10,192.0.2.10
```

```powershell
.\ts-audit.ps1 -NodesPath "$env:USERPROFILE\tailscale-nodes.csv"
```

每行检查 TailnetIP 和 PublicIP 的 TCP 22、9100，默认每次最多等待 2 秒；不登录、不发送应用数据。PublicIP 可留空；多个公网 IPv4/IPv6 地址分别增加行。必须填写 IP 字面量，不接受域名。两脚本支持 `-AsObject` 供后续处理，不自动保存结果。

| 结果 | 含义 |
| --- | --- |
| Reachable | 当前电脑成功建立 TCP 连接；不等于 SSH 登录或 exporter 正常 |
| RefusedHere | 当前路径收到拒绝；不能证明对其他来源也关闭 |
| TimeoutUnknown | 超时，可能被过滤、路由不通或主机无响应 |
| ErrorUnknown | 其他连接错误，无法判断 |
| NotConfigured | 未提供地址，未检查 |

PublicIP 的 Reachable 需要关注，但本机 TUN、VPN、出口节点、分流规则可能改变探测来源。任何其他结果都**不能证明公网未暴露**，需结合外部独立探测、IPv4/IPv6、防火墙及云安全规则核实。此工具不验证 UDP/HY2，也不自动关闭端口。

## 最小权限模板

`policy.example.hujson` 仅允许管理电脑 → server TCP 22、monitor → server TCP 9100；其余未授权流量默认拒绝。适用于普通 OpenSSH + WindTerm，不启用 Tailscale SSH。

模板不自动发布。先备份现有 Policy，在官方编辑器中按实际设备分配标签并运行内置 tests，再人工决定应用。规则是累加的：保留旧的全放行规则会破坏隔离；直接覆盖又可能中断现有访问。管理电脑与 monitor 标签应分开，E2 如也要接受管理连接，可同时标记 monitor 和 server；其他服务器不要获得管理标签。给个人设备打标签会改变其用户身份语义，应先核对现有权限。

按此模板，Windows → 9100 预期不通；监控通路必须从 E2 另行验证。本版不迁移 Prometheus、不修改 HY2/GOST/nftables，不包含网页仪表盘。只有尾网策略无法控制公网访问。

真实清单、状态输出、密钥和凭证均不要放进此公共仓库。升级时同步官方代码；本版修改集中于 `personal/`，未来上游新增同名目录时仍需检查冲突。

## 验证

```powershell
.\test-personal.ps1
```

离线测试使用模拟 CLI 和本机临时 TCP 监听，不接触真实 VPS。它不能代替实际尾网连通性验证；Policy 的 tests 还需在官方编辑器验证。
