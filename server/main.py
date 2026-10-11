import os
import re
import secrets
import tempfile
from pathlib import Path

import yt_dlp
from fastapi import Depends, FastAPI, Header, HTTPException, Query
from fastapi.responses import FileResponse
from starlette.background import BackgroundTask

API_KEY = os.environ.get("API_KEY", "")
VIDEO_ID = re.compile(r"^[A-Za-z0-9_-]{11}$")

app = FastAPI(title="Aether YouTube server")


def require_key(x_api_key: str | None = Header(default=None)) -> None:
    if not API_KEY:
        raise HTTPException(status_code=500, detail="API_KEY is not configured")
    if x_api_key is None or not secrets.compare_digest(x_api_key, API_KEY):
        raise HTTPException(status_code=401, detail="Invalid API key")


def _entry(info: dict) -> dict:
    video_id = info.get("id")
    thumbnails = info.get("thumbnails") or []
    thumbnail = info.get("thumbnail") or (thumbnails[-1].get("url", "") if thumbnails else "")
    return {
        "id": video_id,
        "title": info.get("title") or "Unknown title",
        "author": info.get("uploader") or info.get("channel") or "Unknown",
        "duration": info.get("duration"),
        "thumbnail": thumbnail,
        "url": f"https://www.youtube.com/watch?v={video_id}",
    }


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.get("/search", dependencies=[Depends(require_key)])
def search(
    q: str = Query(min_length=1, max_length=200),
    limit: int = Query(default=15, ge=1, le=25),
) -> dict:
    opts = {"quiet": True, "no_warnings": True, "skip_download": True, "extract_flat": "in_playlist"}
    try:
        with yt_dlp.YoutubeDL(opts) as ydl:
            data = ydl.extract_info(f"ytsearch{limit}:{q}", download=False)
    except yt_dlp.utils.YoutubeDLError as e:
        raise HTTPException(status_code=502, detail=f"Search failed: {e}") from e

    entries = [e for e in (data or {}).get("entries", []) if e and e.get("id")]
    return {"results": [_entry(e) for e in entries]}


@app.get("/audio/{video_id}", dependencies=[Depends(require_key)])
def audio(video_id: str) -> FileResponse:
    if not VIDEO_ID.match(video_id):
        raise HTTPException(status_code=400, detail="Invalid video id")

    tmp = tempfile.TemporaryDirectory(prefix="aether-")
    opts = {
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "format": "bestaudio[ext=m4a]/bestaudio",
        "outtmpl": str(Path(tmp.name) / "%(id)s.%(ext)s"),
    }
    try:
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(f"https://www.youtube.com/watch?v={video_id}", download=True)
            path = Path(ydl.prepare_filename(info))
    except yt_dlp.utils.YoutubeDLError as e:
        tmp.cleanup()
        raise HTTPException(status_code=502, detail=f"Download failed: {e}") from e

    if not path.is_file():
        tmp.cleanup()
        raise HTTPException(status_code=502, detail="Download produced no file")

    media_type = "audio/mp4" if path.suffix == ".m4a" else "audio/webm"
    return FileResponse(
        path,
        media_type=media_type,
        filename=path.name,
        background=BackgroundTask(tmp.cleanup),
    )
