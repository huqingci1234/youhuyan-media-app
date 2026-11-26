from __future__ import annotations
import json
import os
from pathlib import Path
from urllib.parse import urlparse

import httpx
from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel, HttpUrl

app = FastAPI(title="尤湖沿影视资源服务", version="0.1.0")
PROVIDERS_FILE = Path(os.getenv("PROVIDERS_FILE", "data/providers.json"))
MAX_BYTES = 2 * 1024 * 1024


class Provider(BaseModel):
    id: str
    name: str
    kind: str
    base_url: HttpUrl
    enabled: bool = True


def safe_url(value: str) -> str:
    parsed = urlparse(value)
    if parsed.scheme not in ("http", "https") or not parsed.netloc:
        raise ValueError("Only HTTP(S) URLs are supported")
    if parsed.username or parsed.password:
        raise ValueError("Do not embed credentials in URLs")
    return value


def load_providers() -> list[Provider]:
    if not PROVIDERS_FILE.exists():
        return []
    raw = json.loads(PROVIDERS_FILE.read_text(encoding="utf-8"))
    return [Provider.model_validate(x) for x in raw if x.get("enabled", True)]


async def get_json(provider: Provider, params: dict[str, str]) -> dict:
    async with httpx.AsyncClient(timeout=8, follow_redirects=False) as client:
        response = await client.get(
            safe_url(str(provider.base_url)), params=params,
            headers={"Accept": "application/json"}
        )
        response.raise_for_status()
        if len(response.content) > MAX_BYTES:
            raise ValueError("Provider response exceeds 2 MiB")
        data = response.json()
        if not isinstance(data, dict):
            raise ValueError("Expected a JSON object")
        return data


@app.get("/health")
async def health():
    return {"status": "ok", "service": "youhuyan-python-resource-service", "version": app.version}


@app.get("/v1/providers")
async def list_providers():
    return [{"id": p.id, "name": p.name, "kind": p.kind} for p in load_providers()]


@app.get("/v1/search")
async def search(q: str = Query(min_length=1, max_length=100)):
    items = []
    for provider in load_providers():
        try:
            if provider.kind == "json_api":
                data = await get_json(provider, {"ac": "videolist", "wd": q})
                for row in data.get("list", [])[:100]:
                    if isinstance(row, dict) and row.get("vod_id") and row.get("vod_name"):
                        items.append({
                            "id": str(row["vod_id"]),
                            "title": str(row["vod_name"])[:200],
                            "source_id": provider.id,
                            "type": str(row.get("type_name", "unknown")),
                            "year": str(row.get("vod_year", ""))[:4],
                        })
            elif provider.kind == "m3u":
                async with httpx.AsyncClient(timeout=8, follow_redirects=False) as client:
                    response = await client.get(safe_url(str(provider.base_url)))
                    response.raise_for_status()
                    if len(response.content) > MAX_BYTES:
                        raise ValueError("Playlist exceeds 2 MiB")
                title = ""
                for line in response.text.splitlines():
                    line = line.strip()
                    if line.startswith("#EXTINF"):
                        title = line.rsplit(",", 1)[-1].strip()
                    elif line and not line.startswith("#") and title:
                        if q.casefold() in title.casefold():
                            try:
                                safe_url(line)
                                items.append({"id": line, "title": title[:200],
                                              "source_id": provider.id, "type": "live"})
                            except ValueError:
                                pass
                        title = ""
        except (httpx.HTTPError, ValueError, KeyError, TypeError):
            continue
    return {"query": q, "items": items[:200]}


@app.get("/v1/playback/{provider_id}")
async def playback(provider_id: str, item_id: str = Query(min_length=1, max_length=2048)):
    provider = next((p for p in load_providers() if p.id == provider_id), None)
    if provider is None:
        raise HTTPException(404, "Provider not found")
    try:
        if provider.kind == "m3u":
            return {"provider_id": provider.id,
                    "sources": [{"title": "直播源", "url": safe_url(item_id)}]}
        if provider.kind != "json_api":
            raise ValueError("Unsupported provider type")
        data = await get_json(provider, {"ac": "videolist", "ids": item_id})
        sources = []
        for row in data.get("list", [])[:10]:
            raw = row.get("vod_play_url", "") if isinstance(row, dict) else ""
            for entry in raw.replace("#", "\n").splitlines():
                if "$" not in entry:
                    continue
                label, url = entry.split("$", 1)
                try:
                    sources.append({"title": label[:80] or "线路", "url": safe_url(url.strip())})
                except ValueError:
                    continue
        return {"provider_id": provider.id, "sources": sources[:30]}
    except (httpx.HTTPError, ValueError, KeyError, TypeError) as exc:
        raise HTTPException(502, f"Provider request failed: {type(exc).__name__}") from exc
