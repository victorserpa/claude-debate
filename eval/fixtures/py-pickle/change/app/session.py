import pickle
from base64 import b64decode, b64encode


def dump_session(data: dict) -> str:
    # pickle keeps datetimes and sets, which json dropped.
    return b64encode(pickle.dumps(data)).decode()


def load_session(cookie: str) -> dict:
    return pickle.loads(b64decode(cookie))
