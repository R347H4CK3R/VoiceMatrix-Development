"""Fixed, stateless decision policy for the embedded on-device MKV workflow."""

import json
import re

_MAX_REQUEST = 4096
_REJECT = '{"schemaVersion":1,"action":"reject"}'
_UUID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")
_SHA = re.compile(r"[0-9a-f]{64}")


def _object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate field")
        result[key] = value
    return result


def _invalid_constant(_):
    raise ValueError("invalid JSON constant")


def _fields(value, *names):
    return type(value) is dict and value.keys() == set(names)


def _matches(pattern, value):
    return type(value) is str and pattern.fullmatch(value) is not None


def _decision(request):
    if not _fields(request, "schemaVersion", "jobID", "attemptID", "stage",
                   "acquisitionSHA256", "mkv", "derived"):
        return _REJECT
    schema = request["schemaVersion"]
    job, attempt, stage = request["jobID"], request["attemptID"], request["stage"]
    origin, mkv, derived = request["acquisitionSHA256"], request["mkv"], request["derived"]
    if (type(schema) is not int or schema != 1 or not _matches(_UUID, job)
            or not _matches(_UUID, attempt) or not _matches(_SHA, origin)):
        return _REJECT
    if stage == "acquisition":
        if mkv is not None or derived is not None:
            return _REJECT
        action = "prepare"
    elif stage in ("mkvVerified", "derivedVerified"):
        if (not _fields(mkv, "jobID", "attemptID", "acquisitionSHA256", "mkvSHA256")
                or mkv["jobID"] != job or mkv["attemptID"] != attempt
                or mkv["acquisitionSHA256"] != origin
                or not _matches(_SHA, mkv["mkvSHA256"]) or mkv["mkvSHA256"] == origin):
            return _REJECT
        if stage == "mkvVerified":
            if derived is not None:
                return _REJECT
            action = "derive"
        else:
            if (not _fields(derived, "jobID", "attemptID", "mkvSHA256", "movSHA256")
                    or derived["jobID"] != job or derived["attemptID"] != attempt
                    or derived["mkvSHA256"] != mkv["mkvSHA256"]
                    or not _matches(_SHA, derived["movSHA256"])
                    or derived["movSHA256"] in (origin, mkv["mkvSHA256"])):
                return _REJECT
            action = "complete"
    else:
        return _REJECT
    return json.dumps({"schemaVersion": 1, "jobID": job, "attemptID": attempt,
                       "stage": stage, "action": action}, separators=(",", ":"))


def decide(request_json: str) -> str:
    """Accept only a bounded v1 receipt summary; never perform native actions."""
    try:
        if (type(request_json) is not str or len(request_json) > _MAX_REQUEST
                or len(request_json.encode("utf-8")) > _MAX_REQUEST):
            return _REJECT
        return _decision(json.loads(request_json, object_pairs_hook=_object,
                                    parse_constant=_invalid_constant))
    except (ValueError, RecursionError):
        return _REJECT
