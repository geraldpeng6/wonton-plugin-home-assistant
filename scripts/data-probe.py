"""数据钩子的请求端：进 HA 容器跑，直连 HA 的回环（127.0.0.1:8123）。
与 init/onboard.py 同一条路：HA 的 trusted_networks 只认 127.0.0.1/32，容器与宿主同网络栈，
回环请求被当作主人，Bearer 在直连下可用。不走核心网关中继：中继时 Authorization 到不了 HA，
REST 会拿到 401（冒烟 run 42491076170 实测）。
用法：python3 - write|check，标记从 MARKER 环境变量读。
"""

import asyncio
import os
import sys

import aiohttp

MODE = sys.argv[1]
MARKER = os.environ["MARKER"]
BASE = "http://127.0.0.1:8123"
CLIENT = BASE + "/"


async def request(session, method, path, **kwargs):
    async with session.request(method, BASE + path, **kwargs) as response:
        response.raise_for_status()
        return await response.json()


async def main():
    async with aiohttp.ClientSession(trust_env=False,
                                     timeout=aiohttp.ClientTimeout(total=30)) as session:
        flow = await request(session, "POST", "/auth/login_flow", json={
            "client_id": CLIENT, "redirect_uri": CLIENT,
            "handler": ["trusted_networks", None],
        })
        assert flow["type"] == "create_entry", f"可信回环登录没有直接认出主人：{flow}"
        tokens = await request(session, "POST", "/auth/token", data={
            "grant_type": "authorization_code", "client_id": CLIENT, "code": flow["result"],
        })
        session.headers["Authorization"] = "Bearer " + tokens["access_token"]
        url = "/api/config/automation/config/wonton_smoke"
        if MODE == "write":
            payload = {"alias": MARKER,
                       "trigger": [{"platform": "time", "at": "03:33:33"}],
                       "condition": [],
                       "action": [{"action": "homeassistant.update_entity"}]}
            await request(session, "POST", url, json=payload)
        else:
            body = await request(session, "GET", url)
            assert body.get("alias") == MARKER, \
                f"自动化别名对不上：写了 {MARKER}，读到 {body.get('alias')}"
        # 令牌用完即焚；/auth/revoke 返回非 JSON，直接看状态码，失败只提示，不影响数据钩子的结论
        try:
            async with session.post(BASE + "/auth/revoke", data={"token": tokens["refresh_token"]}) as response:
                if response.status >= 400:
                    print(f"提示：refresh_token 吊销返回 HTTP {response.status}", file=sys.stderr)
        except Exception as error:  # noqa: BLE001 # 吊销失败不改变写入/读回的结论
            print(f"提示：refresh_token 吊销失败（{error}）", file=sys.stderr)


asyncio.run(main())
