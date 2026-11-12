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
  container="wonton-$SMOKE_INSTANCE--$SMOKE_SLUG--home-assistant"
  docker exec -i -e "MARKER=$2" "$container" \
    python3 - "$1" <"$SMOKE_DIR/scripts/data-probe.py"
}

data_write() {
  local marker
  [[ -n "${SMOKE_STATE:-}" ]] || { echo "SMOKE_STATE 没设" >&2; return 1; }
  marker="wonton-smoke-$(od -An -N4 -tx4 /dev/urandom | tr -d ' \n')"
  ha_data_py write "$marker" || { echo "建自动化失败" >&2; return 1; }
  printf '%s' "$marker" >"$SMOKE_STATE" || { echo "标记写不进 $SMOKE_STATE" >&2; return 1; }
}

data_check() {
  local marker
  marker="$(cat "$SMOKE_STATE" 2>/dev/null)" || { echo "读不到 $SMOKE_STATE（data_write 没跑过？）" >&2; return 1; }
  ha_data_py check "$marker" || { echo "重装后读不回写的自动化" >&2; return 1; }
}

identity_check() {
  local cookie container
  container="wonton-$SMOKE_INSTANCE--$SMOKE_SLUG--home-assistant"
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
    "$SMOKE_WEB_URL" "$SMOKE_OWNER" <"$SMOKE_DIR/scripts/gateway-probe.py"
}
