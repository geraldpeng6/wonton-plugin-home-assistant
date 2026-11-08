# shellcheck shell=bash
# 请求和 WebSocket 都走核心网关；上游镜像自带 aiohttp（Apache-2.0），宿主不用安装依赖。
web_assert() { grep -q '<home-assistant'; }

# 数据：一条真实用户数据——建自动化（落 automations.yaml，升级/重装后还在），别名带随机标记；
# 固定 id wonton_smoke，重复写是更新，不堆积。
# 请求从容器里直连 HA 的回环（scripts/data-probe.py，与 init/onboard.py 同一条路：trusted_networks
# 只认 127.0.0.1/32，回环被当作主人，Bearer 直连可用）。不走核心网关中继：中继时 Authorization
# 到不了 HA，REST 拿到 401（run 42491076170 实测）。
ha_data_py() { # <write|check> <marker>
  local container
  container="wonton-${SMOKE_INSTANCE:-${E2E_INSTANCE:?}}--${SMOKE_SLUG:-${E2E_SLUG:?}}--home-assistant"
  docker exec -i -e "MARKER=$2" "$container" \
    python3 - "$1" <"${SMOKE_DIR:-${E2E_DIR:?}}/scripts/data-probe.py"
}

# SMOKE_STATE 按套件契约是状态目录（.wonton），标记作为目录里的文件存放；兼容被当成文件用的旧形态。
ha_marker() { [[ -d "$SMOKE_STATE" ]] && printf '%s/data-marker' "$SMOKE_STATE" || printf '%s' "$SMOKE_STATE"; }

data_write() {
  local marker_file marker
  [[ -n "${SMOKE_STATE:-}" ]] || { echo "SMOKE_STATE 没设" >&2; return 1; }
  marker="wonton-smoke-$(od -An -N4 -tx4 /dev/urandom | tr -d ' \n')"
  ha_data_py write "$marker" || { echo "建自动化失败" >&2; return 1; }
  marker_file="$(ha_marker)"
  printf '%s' "$marker" >"$marker_file" || { echo "标记写不进 $marker_file" >&2; return 1; }
}

data_check() {
  local marker_file marker
  marker_file="$(ha_marker)"
  marker="$(cat "$marker_file" 2>/dev/null)" || { echo "读不到 $marker_file（data_write 没跑过？）" >&2; return 1; }
  ha_data_py check "$marker" || { echo "重装后读不回写的自动化" >&2; return 1; }
}

identity_check() {
  local cookie container
  # 插件自己的 smoke 有 SMOKE_*；e2e 的 smoke_env 不给 SMOKE_DIR/SMOKE_SLUG，用 E2E_* 补。
  container="wonton-${SMOKE_INSTANCE:-${E2E_INSTANCE:?}}--${SMOKE_SLUG:-${E2E_SLUG:?}}--home-assistant"
  cookie="$(python3 - "$SMOKE_JAR" "$SMOKE_WEB_URL" <<'PY'
import http.cookiejar, sys, urllib.request
jar = http.cookiejar.MozillaCookieJar(sys.argv[1])
jar.load(ignore_discard=True, ignore_expires=False)
request = urllib.request.Request(sys.argv[2])
jar.add_cookie_header(request)
print(request.get_header("Cookie", ""))
PY
  )" || return 1
  docker exec -i -e "GATEWAY_COOKIE=$cookie" "$container" python3 - \
    "$SMOKE_WEB_URL" "$SMOKE_OWNER" <"${SMOKE_DIR:-${E2E_DIR:?}}/scripts/gateway-probe.py"
}
