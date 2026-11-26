import pytest
from app.main import safe_url


def test_accepts_http_url():
    assert safe_url("https://example.com/api") == "https://example.com/api"


@pytest.mark.parametrize("url", ["file:///etc/passwd", "javascript:alert(1)", "//example.com/x", "https://u:p@example.com/a"])
def test_rejects_unsafe_url(url):
    with pytest.raises(ValueError):
        safe_url(url)
