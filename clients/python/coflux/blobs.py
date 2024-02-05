import httpx
import hashlib
from pathlib import Path

CHUNK_SIZE = 5 // 2**18


def _hash_file(filename):
    hash = hashlib.sha256()
    with open(filename, "rb") as file:
        for chunk in iter(lambda: file.read(4096), b""):
            hash.update(chunk)
    return hash.hexdigest()


class Store:
    def __init__(self, url_format: str):
        self._url_format = url_format

    def __enter__(self):
        self._client = httpx.Client()
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self._client.close()

    def _url(self, key: str) -> str:
        return self._url_format.format(key=key)

    def get(self, key: str) -> bytes:
        response = self._client.get(self._url(key))
        response.raise_for_status()
        return response.content

    def download(self, key: str, path: Path) -> None:
        with path.open("wb") as file:
            with self._client.stream("GET", self._url(key)) as response:
                response.raise_for_status()
                for chunk in response.iter_bytes():
                    file.write(chunk)

    def _exists(self, key: str) -> bool:
        return self._client.head(self._url(key)).status_code == 200

    def put(self, content: bytes) -> str:
        key = hashlib.sha256(content).hexdigest()
        if not self._exists(key):
            self._client.put(self._url(key), content=content).raise_for_status()
        return key

    def upload(self, path: Path) -> str:
        key = _hash_file(path)
        if not self._exists(key):
            with path.open("rb") as file:
                self._client.put(self._url(key), content=file).raise_for_status()
        return key
