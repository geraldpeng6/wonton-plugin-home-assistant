# shellcheck shell=bash
# 请求和 WebSocket 都走核心网关；上游镜像自带 aiohttp（Apache-2.0），宿主不用安装依赖。
web_assert() { grep -q '<home-assistant'; }

# 可信回环登录链换 HA token：请求经网关转发，HA 只见回环，trusted_networks 直接认出主人，
# 用授权码换 access_token 后才能调 HA 自己的 API。
_core_base() { printf '%s' "${E2E_BASE:-${SMOKE_BASE:-}}"; }

# 数据钩子跑在网页项之前，套件还没建会话 Jar：核心登录，再走一次插件的登录跳转——网关的会话 Cookie
# 落在插件主机上，网关才放行到 HA。
_gateway_login() { # <base>
  local token
  token="${E2E_TOKEN:-${SMOKE_TOKEN:-}}"
  [[ -n "$token" ]] || { echo "没有主人令牌"; return 1; }
  curl -sS --noproxy '*' -o /dev/null -b "$SMOKE_JAR" -c "$SMOKE_JAR" \
    --data-urlencode "token=$token" "$(_core_base)/_wonton/login" &&
    curl -sS --noproxy '*' -o /dev/null -L -b "$SMOKE_JAR" -c "$SMOKE_JAR" -H 'Accept: text/html' "${1%/}/"
}

_ha_token() {
  local base client flow resp
  base="${SMOKE_WEB_URL%/}"
  client="$base/"
  _gateway_login "$base" || { echo "网关会话建不了"; return 1; }
  flow="$(curl -sS --noproxy '*' --fail-with-body -b "$SMOKE_JAR" -H 'Content-Type: application/json' \
    -d '{"client_id":"'"$client"'","redirect_uri":"'"$client"'","handler":["trusted_networks",null]}' \
    "$SMOKE_WEB_URL/auth/login_flow")" || { echo "可信回环登录失败：$flow"; return 1; }
  local code
  code="$(jq -er '.result // empty' <<<"$flow")" || { echo "登录没有直接认出主人：$flow"; return 1; }
  resp="$(curl -sS --noproxy '*' --fail-with-body -b "$SMOKE_JAR" -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode 'grant_type=authorization_code' --data-urlencode "client_id=$client" \
    --data-urlencode "code=$code" "$SMOKE_WEB_URL/auth/token")" || { echo "换 token 失败：$resp"; return 1; }
  jq -er '.access_token // empty' <<<"$resp" || { echo "token 响应里没有 access_token：$resp"; return 1; }
}

# 数据：一条真实用户数据——建自动化（落 automations.yaml，升级后还在），别名带随机标记；
# 固定 id wonton_smoke，重复写是更新，不堆积。
data_write() {
  local marker token resp
  [[ -n "${SMOKE_STATE:-}" ]] || { echo "SMOKE_STATE 没设"; return 1; }
  marker="wonton-smoke-$(od -An -N4 -tx4 /dev/urandom | tr -d ' \n')"
  token="$(_ha_token)" || return 1
  resp="$(curl -sS --noproxy '*' --fail-with-body -b "$SMOKE_JAR" -X POST \
    -H "Authorization: Bearer $token" -H 'Content-Type: application/json' \
    -d '{"alias":"'"$marker"'","trigger":[{"platform":"time","at":"03:33:33"}],"condition":[],"action":[{"action":"homeassistant.update_entity"}]}' \
    "$SMOKE_WEB_URL/api/config/automation/config/wonton_smoke")" || { echo "建自动化失败：$resp"; return 1; }
  printf '%s' "$marker" >"$SMOKE_STATE"
}

data_check() {
  local marker token resp code body seen
  [[ -n "${SMOKE_STATE:-}" ]] || { echo "SMOKE_STATE 没设"; return 1; }
  marker="$(cat "$SMOKE_STATE")" || { echo "读不到 $SMOKE_STATE"; return 1; }
  token="$(_ha_token)" || return 1
  resp="$(curl -sS --noproxy '*' -w $'\n%{http_code}' -b "$SMOKE_JAR" -H "Authorization: Bearer $token" \
    -H 'Accept: application/json' "$SMOKE_WEB_URL/api/config/automation/config/wonton_smoke")"
  code="${resp##*$'\n'}"
  body="${resp%$'\n'*}"
  [[ "$code" == 200 ]] || { echo "自动化 wonton_smoke 读不到（HTTP $code）：$(head -c 200 <<<"$body")"; return 1; }
  seen="$(jq -r '.alias // empty' <<<"$body")"
  [[ "$seen" == "$marker" ]] || { echo "自动化别名对不上：写了 $marker，读到 $seen"; return 1; }
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
