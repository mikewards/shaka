"""
Smoke tests for tide_engine (run only when FES2022 data is available).

Usage:
    FES_DATA_DIR=/path/to/fes2022 python -m pytest tests/test_engine.py -v
"""

import os
import pytest

FES_AVAILABLE = os.path.isdir(os.environ.get("FES_DATA_DIR", "/data/fes2022"))

pytestmark = pytest.mark.skipif(not FES_AVAILABLE, reason="FES2022 data not available")


@pytest.fixture(scope="module", autouse=True)
def _load_model():
    from tide_engine import load_model
    load_model(os.environ.get("FES_DATA_DIR", "/data/fes2022"))


def test_predict_chart_pipeline():
    from tide_engine import predict_chart

    result = predict_chart(33.62, -117.93, "2026-03-08", days=1, step_minutes=30)

    assert result["datum"] == "MSL"
    assert result["model"] == "FES2022"
    assert len(result["points"]) >= 24
    assert len(result["extremes"]) >= 2

    for p in result["points"]:
        assert -20 < p["height_ft"] < 20
        assert p["epoch_ms"] > 0


def test_predict_summary_pipeline():
    from tide_engine import predict_summary

    result = predict_summary(21.27, -157.82)

    assert result["datum"] == "MSL"
    assert result["tide_state"] in ("rising", "falling", "unknown")
    assert isinstance(result["current_height_ft"], float)


def test_timezone_lookup():
    from tide_engine import get_timezone

    assert get_timezone(21.3, -157.8) == "Pacific/Honolulu"
    assert get_timezone(33.6, -117.9) == "America/Los_Angeles"
    assert get_timezone(-27.5, 153.4) == "Australia/Brisbane"
