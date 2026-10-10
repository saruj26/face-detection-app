import json

from app.assets import resolve_asset_url
from app.config import BACKEND_DIR


def test_resolve_relative_with_request_base():
    assert resolve_asset_url("/static/x.png", "", "http://10.0.2.2:8000/") == "http://10.0.2.2:8000/static/x.png"


def test_resolve_relative_with_asset_base():
    assert resolve_asset_url("/static/x.png", "https://cdn.test", "http://h/") == "https://cdn.test/static/x.png"


def test_absolute_unchanged():
    assert resolve_asset_url("https://a/b.png", "https://cdn", "http://h/") == "https://a/b.png"


def test_generated_catalogue_is_consistent():
    items = json.loads((BACKEND_DIR / "static/glasses/catalogue.json").read_text())
    assert len(items) == 10
    assert len({i["name"] for i in items}) == 10
    for item in items:
        fit = item["fit_metadata"]
        assert 0.15 < fit["eye_span_ratio"] < 0.5
        assert 0 < fit["anchor_y"] < 1
        for key in ("catalogue_image_url", "transparent_overlay_url"):
            assert (BACKEND_DIR / item[key].lstrip("/")).exists()
