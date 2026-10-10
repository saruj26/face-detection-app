from app.database import normalize_database_url

NEON = "postgresql://user:pw@ep-x-pooler.region.aws.neon.tech/neondb?sslmode=require&channel_binding=require"


def test_neon_url_uses_psycopg3_and_keeps_ssl_params():
    url = normalize_database_url(NEON)
    assert url.drivername == "postgresql+psycopg"
    assert url.query["sslmode"] == "require"
    assert url.query["channel_binding"] == "require"
    assert url.host == "ep-x-pooler.region.aws.neon.tech"


def test_legacy_postgres_scheme_is_normalised():
    assert normalize_database_url("postgres://u:p@h/db").drivername == "postgresql+psycopg"


def test_password_is_hidden_when_rendered():
    assert "pw" not in normalize_database_url(NEON).render_as_string(hide_password=True)
