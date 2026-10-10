"""Turn image references stored in the database into absolute URLs."""


def resolve_asset_url(stored: str, asset_base_url: str, request_base_url: str) -> str:
    """Return an absolute URL for an image reference.

    * Absolute URLs (e.g. object storage / CDN) are returned unchanged.
    * Relative paths (bundled demo assets such as ``/static/glasses/x.png``) are
      joined with ``ASSET_BASE_URL`` when configured, otherwise with the base URL
      the client used to reach this API, so the same database rows work for an
      emulator (10.0.2.2) and a physical phone (LAN IP).
    """
    if stored.startswith(("http://", "https://")):
        return stored
    base = (asset_base_url or request_base_url).rstrip("/")
    return f"{base}/{stored.lstrip('/')}"
