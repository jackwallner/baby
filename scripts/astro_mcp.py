#!/usr/bin/env python3
"""Minimal Astro MCP client for setup scripts."""
from __future__ import annotations

import json
import time
import urllib.error
import urllib.request
from typing import Any

DEFAULT_MCP_URL = "http://127.0.0.1:8089/mcp"


def call(mcp_url: str, tool: str, arguments: dict[str, Any], req_id: int = 1, timeout: int = 300) -> Any:
    payload = {
        "jsonrpc": "2.0",
        "id": req_id,
        "method": "tools/call",
        "params": {"name": tool, "arguments": arguments},
    }
    req = urllib.request.Request(
        mcp_url,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        body = json.loads(resp.read())
    if "error" in body:
        raise RuntimeError(body["error"])
    content = body["result"]["content"][0]["text"]
    return json.loads(content) if content.strip().startswith(("[", "{")) else content


def ping(mcp_url: str = DEFAULT_MCP_URL) -> bool:
    try:
        payload = {
            "jsonrpc": "2.0",
            "id": 0,
            "method": "initialize",
            "params": {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": {"name": "astro_mcp.py", "version": "1.0"},
            },
        }
        req = urllib.request.Request(
            mcp_url,
            data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=5) as resp:
            return resp.status == 200
    except (urllib.error.URLError, TimeoutError, OSError):
        return False


def list_apps(mcp_url: str = DEFAULT_MCP_URL) -> list[dict[str, Any]]:
    return call(mcp_url, "list_apps", {})


def find_app_id(apps: list[dict[str, Any]], app_name: str) -> str | None:
    name_lower = app_name.lower()
    for app in apps:
        if app.get("name", "").lower() == name_lower:
            return str(app["appId"])
    for app in apps:
        if name_lower in app.get("name", "").lower() or app.get("name", "").lower() in name_lower:
            return str(app["appId"])
    return None


def add_keywords(
    mcp_url: str,
    app_id: str,
    store: str,
    keywords: list[str],
) -> dict[str, Any]:
    results: list[Any] = []
    for i in range(0, len(keywords), 100):
        batch = keywords[i : i + 100]
        results.append(call(mcp_url, "add_keywords", {"appId": app_id, "store": store, "keywords": batch}, req_id=100 + i))
    return {"batches": results}


def remove_keywords(
    mcp_url: str,
    app_id: str,
    store: str,
    keywords: list[str],
) -> dict[str, Any]:
    results: list[Any] = []
    for i in range(0, len(keywords), 100):
        batch = keywords[i : i + 100]
        results.append(
            call(
                mcp_url,
                "remove_keywords",
                {"appId": app_id, "store": store, "keywords": batch},
                req_id=200 + i,
            )
        )
    return {"batches": results}


def ensure_tag(mcp_url: str, name: str, color: str) -> None:
    try:
        call(mcp_url, "manage_tag", {"action": "create", "name": name, "color": color})
    except RuntimeError:
        pass  # already exists


def tag_keyword(mcp_url: str, app_id: str, store: str, keyword: str, tag: str) -> None:
    call(
        mcp_url,
        "set_keyword_tag",
        {"appId": app_id, "store": store, "keyword": keyword, "tag": tag, "action": "add"},
    )
    time.sleep(0.4)
