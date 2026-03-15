"""
FES2022 Tide Microservice

Provides tide predictions for any ocean coordinate using FES2022 + pyTMD.
Designed to run as a Railway service alongside the Shaka Kotlin backend.
"""

import logging
import threading
from contextlib import asynccontextmanager

import uvicorn
from fastapi import FastAPI, HTTPException, Query

from config import AVISO_PASS, AVISO_USER, FES_DATA_DIR, PORT
from startup import ensure_fes_data
from tide_engine import load_model, predict_chart, predict_summary

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger("main")

_ready = threading.Event()


def _init():
    try:
        ensure_fes_data(FES_DATA_DIR, AVISO_USER, AVISO_PASS)
        load_model(FES_DATA_DIR)
        logger.info("Warming up prediction pipeline...")
        import datetime
        today = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")
        predict_chart(0.0, -160.0, today, days=1, step_minutes=30)
        logger.info("Warm-up complete")
        _ready.set()
        logger.info("Tide service ready")
    except Exception:
        logger.exception("Failed to initialize tide service")


@asynccontextmanager
async def lifespan(app: FastAPI):
    thread = threading.Thread(target=_init, daemon=True)
    thread.start()
    yield


app = FastAPI(title="Shaka Tide Service", version="1.0.0", lifespan=lifespan)


@app.get("/health")
async def health():
    if not _ready.is_set():
        return {"status": "loading", "detail": "Downloading FES2022 data..."}
    return {"status": "ok", "model": "FES2022"}


@app.get("/tide/chart")
async def tide_chart(
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
    date: str = Query(None, pattern=r"^\d{4}-\d{2}-\d{2}$"),
    days: int = Query(1, ge=1, le=14),
    step_minutes: int = Query(30, ge=6, le=60),
):
    if not _ready.is_set():
        raise HTTPException(status_code=503, detail="Service not ready")
    try:
        return predict_chart(lat, lon, date, days, step_minutes)
    except Exception as e:
        logger.exception("Chart prediction failed for (%s, %s)", lat, lon)
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/tide/summary")
async def tide_summary(
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
):
    if not _ready.is_set():
        raise HTTPException(status_code=503, detail="Service not ready")
    try:
        return predict_summary(lat, lon)
    except Exception as e:
        logger.exception("Summary prediction failed for (%s, %s)", lat, lon)
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=PORT)
