import httpx
import hashlib
import urllib.parse


class Store:
    def __init__(self, server_host: str):
        self._server_host = server_host

    # TODO: make blob url configurable
    def _url(self, scheme: str, path: str, **kwargs) -> str:
        params = {k: v for k, v in kwargs.items() if v is not None} if kwargs else None
        query_string = f"?{urllib.parse.urlencode(params)}" if params else ""
        return f"{scheme}://{self._server_host}/{path}{query_string}"

    def get(self, key: str) -> bytes:
        with httpx.Client() as client:
            response = client.get(self._url("http", f"blobs/{key}"))
            response.raise_for_status()
            return response.content

    def put(self, content: bytes) -> str:
        key = hashlib.sha256(content).hexdigest()
        # TODO: check whether already uploaded (using head request)?
        with httpx.Client() as client:
            response = client.put(self._url("http", f"blobs/{key}"), content=content)
            response.raise_for_status()
        return key
