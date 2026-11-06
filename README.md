# Home Assistant 云吞插件

开发流程见[插件开发指南](https://github.com/geraldpeng6/wonton-docs/blob/main/develop.md)。

Home Assistant 的云吞插件：宿主网络发现局域网设备，配置和集成保存在插件数据目录。需要支持
`network.host` 和网页中继的核心，清单采用 spec 0.6。

Home Assistant 2026.10.4 没有内置 OIDC。安装通过官方 onboarding 接口创建主人的账号，密码由核心随机生成，
不显示或写入日志；只信任 `127.0.0.1/32`，打开网页不再要求密码。宿主进程和其他宿主网络容器也可使用这个入口，
回环信任不能隔离这些进程。不要把它当作多租户主机的身份边界。

Home Assistant 的 HTTP YAML 配置会进入五分钟待确认状态，所以首次启动预写 `.storage/http` 的 stable 配置，
不保留 HTTP YAML 段。已有数据不覆盖。时区经 `!env_var TZ` 读取核心注入值；中文由上游接口设置，分析偏好首次写为关闭。

核心网关发送 `X-Forwarded-For`；Home Assistant 未启用可信代理时返回 400，而其 trusted_networks 又拒绝可信代理。
因此用官方 nginx（BSD-2-Clause）的配置去掉转发头，保留 Host 和 WebSocket，不注入身份、不自研侧车。
Home Assistant 和 nginx 分别只监听 `127.0.0.1:8123`、`127.0.0.1:18123`，核心经 unix 中继连接后者。
8123 被占时启动明确失败，不换端口或假装健康。

DHCP 发现声明 `NET_RAW`，不使用 `privileged`。蓝牙所需的只读 `/run/dbus` 挂载不在规范允许范围，
因此不申请无法完整使用的 `NET_ADMIN`，真实蓝牙、USB 和串口设备未验证。

## 先跑起来

```bash
scripts/dev.sh up
scripts/dev.sh install
```

`up` 在本机起一套云吞并打印它的地址，用 `scripts/dev.sh token` 输出的用户令牌登录；`install` 列出插件要的权限，确认后
装上并打印插件网页的地址，打开就是装好的 Home Assistant（首次进入无需密码）。

## 仓库里有什么

| 路径 | 内容 |
| --- | --- |
| `docker-compose.yml` | 插件本身：compose 加上 `x-wonton` 清单 |
| `icon.svg`、`web/` | 清单和 compose 引用的文件：图标、交给容器的配置和网页 |
| `screenshots/` | 商店详情页里的截图 |
| `scripts/check.sh` | 检查插件包，规则和安装时一样 |
| `scripts/dev.sh` | 开发环境：起一套云吞，装、重装、卸载插件，看日志 |
| `scripts/smoke-probes.sh` | `scripts/dev.sh smoke` 对这个插件逐项的探测 |
| `scripts/publish.sh` | 发布一个版本：打 tag、推送 |
| `AGENTS.md` | 给人和 AI 编程代理的规则 |
| `LICENSE`、`NOTICE` | 插件许可证、图标等第三方素材的许可和声明 |

## 图标

使用 Home Assistant 官方原版标志，未改色或变形；来源、许可全文和商标说明见 [NOTICE](NOTICE)。
