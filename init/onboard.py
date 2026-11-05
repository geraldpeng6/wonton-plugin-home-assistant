"""Complete upstream onboarding through its HTTP and WebSocket APIs."""

import asyncio
import os

import aiohttp

BASE = "http://127.0.0.1:8123"
CLIENT = BASE + "/"


async def request(session, method, path, **kwargs):
    async with session.request(method, BASE + path, **kwargs) as response:
        if response.status >= 400:
            # Request/response bodies can contain credentials; report only the endpoint and status.
            raise RuntimeError(f"Home Assistant {path} 返回 HTTP {response.status}")
        return await response.json()


async def command(ws, number, kind, **fields):
    await ws.send_json({"id": number, "type": kind, **fields})
    reply = await ws.receive_json(timeout=30)
    if reply.get("id") != number or not reply.get("success"):
        raise RuntimeError(f"Home Assistant WebSocket {kind} 失败")
    return reply.get("result")


async def main():
    timeout = aiohttp.ClientTimeout(total=90)
    async with aiohttp.ClientSession(timeout=timeout, trust_env=False) as session:
        async with session.get(BASE + "/api/onboarding") as response:
            # HA removes onboarding endpoints after a completed installation restarts.
            if response.status == 404:
                print("Home Assistant 已完成初始化，保留原有账号与设置。")
                return
            response.raise_for_status()
            steps = {step["step"]: step["done"] for step in await response.json()}
        if all(steps.values()):
            print("Home Assistant 已完成初始化，保留原有账号与设置。")
            return
        if not steps["user"]:
            user = await request(session, "POST", "/api/onboarding/users", json={
                "name": os.environ["OWNER_NAME"], "username": os.environ["OWNER_NAME"],
                "password": os.environ["OWNER_PASSWORD"], "client_id": CLIENT,
                "language": "zh-Hans",
            })
            code = user["auth_code"]
        else:
            flow = await request(session, "POST", "/auth/login_flow", json={
                "client_id": CLIENT, "redirect_uri": CLIENT,
                "handler": ["trusted_networks", None],
            })
            if flow["type"] != "create_entry":
                raise RuntimeError("Home Assistant 初始化未完成，且回环可信登录没有返回唯一账号。")
            code = flow["result"]
        tokens = await request(session, "POST", "/auth/token", data={
            "grant_type": "authorization_code", "client_id": CLIENT, "code": code,
        })
        session.headers["Authorization"] = "Bearer " + tokens["access_token"]
        try:
            if not steps["core_config"]:
                await request(session, "POST", "/api/onboarding/core_config", json={})
            async with session.ws_connect(BASE + "/api/websocket") as ws:
                if (await ws.receive_json())["type"] != "auth_required":
                    raise RuntimeError("Home Assistant WebSocket 没有要求认证")
                await ws.send_json({"type": "auth", "access_token": tokens["access_token"]})
                if (await ws.receive_json())["type"] != "auth_ok":
                    raise RuntimeError("Home Assistant WebSocket 认证失败")
                await command(ws, 1, "frontend/set_user_data", key="language", value={"language": "zh-Hans"})
            if not steps["analytics"]:
                await request(session, "POST", "/api/onboarding/analytics", json={})
            if not steps["integration"]:
                await request(session, "POST", "/api/onboarding/integration", json={
                    "client_id": CLIENT, "redirect_uri": CLIENT,
                })
            result = await request(session, "GET", "/api/onboarding")
            if not all(step["done"] for step in result):
                raise RuntimeError("Home Assistant onboarding 仍有未完成的步骤")
        finally:
            async with session.post(BASE + "/auth/revoke", data={"token": tokens["refresh_token"]}) as response:
                response.raise_for_status()
        print("Home Assistant 官方 onboarding 完成；中文、可信回环登录已设置，分析与遥测已关闭。")


if __name__ == "__main__":
    asyncio.run(main())
