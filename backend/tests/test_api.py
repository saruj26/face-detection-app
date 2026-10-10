from app.config import get_settings
from app.main import app


def test_health_ok(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok", "database": "ok"}


def test_health_reports_unavailable_database_without_details(client):
    from app.database import get_db

    class BrokenSession:
        def execute(self, *_):
            raise RuntimeError("password=secret host=db")

    app.dependency_overrides[get_db] = lambda: BrokenSession()
    r = client.get("/health")
    assert r.status_code == 503
    assert r.json() == {"status": "degraded", "database": "unavailable"}
    assert "secret" not in r.text


def test_list_glasses(client):
    r = client.get("/glasses")
    assert r.status_code == 200
    body = r.json()
    assert body["total"] == 2
    names = [g["name"] for g in body["items"]]
    assert names == ["Aviator Classic", "Round Wire"]
    first = body["items"][0]
    assert set(first) >= {"id", "name", "category", "price", "currency", "catalogue_image_url",
                          "transparent_overlay_url", "fit_metadata", "created_at"}
    assert first["price"] == 129.0
    assert first["fit_metadata"]["eye_span_ratio"] == 0.29


def test_relative_asset_paths_resolve_against_request_host(client):
    item = client.get("/glasses", headers={"host": "192.168.1.20:8000"}).json()["items"][0]
    assert item["transparent_overlay_url"] == "http://192.168.1.20:8000/static/glasses/a_overlay.png"


def test_absolute_asset_urls_are_unchanged(client):
    item = client.get("/glasses").json()["items"][1]
    assert item["catalogue_image_url"] == "https://cdn.example.com/r_catalogue.png"


def test_asset_base_url_setting_is_used(client, monkeypatch):
    monkeypatch.setenv("ASSET_BASE_URL", "https://bucket.example.com/")
    get_settings.cache_clear()
    try:
        item = client.get("/glasses").json()["items"][0]
        assert item["catalogue_image_url"] == "https://bucket.example.com/static/glasses/a_catalogue.png"
    finally:
        monkeypatch.setenv("ASSET_BASE_URL", "")
        get_settings.cache_clear()


def test_filter_by_category_is_case_insensitive(client):
    body = client.get("/glasses", params={"category": "round"}).json()
    assert body["total"] == 1
    assert body["items"][0]["name"] == "Round Wire"


def test_pagination_validation(client):
    assert client.get("/glasses", params={"limit": 0}).status_code == 422
    body = client.get("/glasses", params={"limit": 1, "offset": 1}).json()
    assert [g["name"] for g in body["items"]] == ["Round Wire"]
    assert body["total"] == 2


def test_get_glasses_by_id(client):
    gid = client.get("/glasses").json()["items"][0]["id"]
    r = client.get(f"/glasses/{gid}")
    assert r.status_code == 200
    assert r.json()["name"] == "Aviator Classic"


def test_get_glasses_not_found(client):
    r = client.get("/glasses/99999")
    assert r.status_code == 404
    assert r.json() == {"detail": "Glasses not found"}


def test_get_glasses_invalid_id(client):
    assert client.get("/glasses/abc").status_code == 422


def test_static_overlay_is_served(client):
    r = client.get("/static/glasses/aviator-classic_overlay.png")
    assert r.status_code == 200
    assert r.headers["content-type"] == "image/png"
