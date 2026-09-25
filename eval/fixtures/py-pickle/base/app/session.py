import json
from base64 import b64decode, b64encode


def dump_session(data: dict) -> str:
    return b64encode(json.dumps(data).encode()).decode()


def load_session(cookie: str) -> dict:
    return json.loads(b64decode(cookie))
