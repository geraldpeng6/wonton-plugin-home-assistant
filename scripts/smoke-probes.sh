# 请求和 WebSocket 都走核心网关；上游镜像自带 aiohttp（Apache-2.0），宿主不用安装依赖。
web_assert() { grep -q '<home-assistant'; }

identity_check() {
  local cookie container
  cookie="$(python3 - "$SMOKE_JAR" "$SMOKE_WEB_URL" <<'PY'
import http.cookiejar, sys, urllib.request
jar = http.cookiejar.MozillaCookieJar(sys.argv[1])
jar.load(ignore_discard=True, ignore_expires=False)
request = urllib.request.Request(sys.argv[2])
jar.add_cookie_header(request)
print(request.get_header("Cookie", ""))
PY
  )" || return 1
  container="wonton-$SMOKE_INSTANCE--$SMOKE_SLUG--home-assistant"
  docker exec -i -e "GATEWAY_COOKIE=$cookie" "$container" python3 - \
    "$SMOKE_WEB_URL" "$SMOKE_OWNER" <"$SMOKE_DIR/scripts/gateway-probe.py"
}
