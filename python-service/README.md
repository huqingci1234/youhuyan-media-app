# 尤湖沿影视 Python 资源服务

供尤湖沿影视手机端与 TV 端共用的 FastAPI 资源服务。

## API
- `GET /health` 健康检查
- `GET /v1/providers` 已启用资源列表
- `GET /v1/search?q=关键词` 搜索 JSON API 或 M3U
- `GET /v1/playback/{provider_id}?item_id=资源ID` 获取播放线路

## 本地运行
```bash
cd python-service
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp data/providers.example.json data/providers.json
uvicorn app.main:app --reload
```

`providers.json` 只填写你拥有或获准使用的 HTTP(S) JSON API / M3U 地址。不要在 URL 中嵌入账号密码。此服务不执行远程 Python、JAR、Spider 或 JavaScript，不绕过付费、DRM 或访问控制。
