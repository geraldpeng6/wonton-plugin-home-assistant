"""Run in the upstream HA image; all application requests traverse the Wonton gateway."""

import asyncio
import os
import socket
import sys

import aiohttp


class LocalhostResolver(aiohttp.resolver.DefaultResolver):
    async def resolve(self, host, port=0, family=socket.AF_INET):
        if host.endswith(".localhost"):
            return [{"hostname": host, "host": "127.0.0.1", "port": port,
                     "family": socket.AF_INET, "proto": 0, "flags": 0}]
        return await super().resolve(host, port, family)


async def main():
    base, owner = sys.argv[1:3]
    base = base.rstrip("/")
    client = base + "/"
    connector = aiohttp.TCPConnector(resolver=LocalhostResolver())
    async with aiohttp.ClientSession(connector=connector, trust_env=False,
                                     timeout=aiohttp.ClientTimeout(total=30)) as session:
        async with session.get(base + "/api/config", allow_redirects=False) as response:
            assert response.status == 401, "网关没有拒绝匿名 API 请求"
        session.headers["Cookie"] = os.environ["GATEWAY_COOKIE"]
        session.headers["Origin"] = base
        async with session.post(base + "/auth/login_flow", json={
            "client_id": client, "redirect_uri": client,
            "handler": ["trusted_networks", None],
        }) as response:
            response.raise_for_status()
            flow = await response.json()
            assert flow["type"] == "create_entry", "可信回环登录没有直接认出主人"
        async with session.post(base + "/auth/token", data={
            "grant_type": "authorization_code", "client_id": client, "code": flow["result"],
        }) as response:
            response.raise_for_status()
            tokens = await response.json()
        try:
            async with session.ws_connect(base + "/api/websocket") as ws:
                assert (await ws.receive_json())["type"] == "auth_required"
                await ws.send_json({"type": "auth", "access_token": tokens["access_token"]})
                assert (await ws.receive_json())["type"] == "auth_ok"
                results = {}
                for number, kind in enumerate([
                    "auth/current_user", "get_config", "http/config", "analytics",
                    "config_entries/flow/progress", "frontend/get_user_data",
                ], 1):
                    await ws.send_json({"id": number, "type": kind})
                    reply = await ws.receive_json(timeout=30)
                    assert reply.get("id") == number and reply.get("success"), f"{kind} 失败"
                    results[kind] = reply["result"]
                user = results["auth/current_user"]
                assert user["name"] == owner and user["is_owner"] and user["is_admin"], "不是主人管理员"
                config = results["get_config"]
                assert config["state"] == "RUNNING" and config["language"] == "zh-Hans"
                http = results["http/config"]
                assert http["active_config_type"] == "stable" and http["pending"] is None
                assert http["revert_at"] is None and http["stable"]["server_host"] == ["127.0.0.1"]
                assert http["stable"]["server_port"] == 8123
                assert not any(results["analytics"]["preferences"].values()), "分析没有全部关闭"
                assert results["frontend/get_user_data"]["value"]["language"]["language"] == "zh-Hans"
                flows = results["config_entries/flow/progress"]
                discovered = sorted({f["handler"] for f in flows if f["context"]["source"] in {"zeroconf", "ssdp", "dhcp"}})
                print("PASS 网关匿名拒绝、主人管理员、免密码登录、WebSocket、中文和遥测关闭")
                print("PASS HTTP stable 回环配置；时区：" + config["time_zone"])
                print("自动发现类别：" + ", ".join(discovered))
        finally:
            async with session.post(base + "/auth/revoke", data={"token": tokens["refresh_token"]}) as response:
                response.raise_for_status()


asyncio.run(main())
