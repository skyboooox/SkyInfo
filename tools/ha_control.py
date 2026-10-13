import argparse
import json
import os
import re
import urllib.error
import urllib.request
import time
from pathlib import Path


def catalog():
    fields = json.loads((Path(__file__).resolve().parents[1] / "app/assets/entities.json").read_text())
    return [{"id": name, "name": label, "min": 0, "max": 1} for name, label in
            [("app_overlay", "悬浮条开关"), ("app_collect", "采集开关"), ("app_publish", "上报开关"), ("app_refresh", "刷新读数")]] + [
                {**item, "min": min(o["value"] for o in item["options"]), "max": max(o["value"] for o in item["options"])} for item in fields]



def script_config(target):
    assert re.fullmatch(r"[a-z0-9_]{1,48}", target)
    return {
        "alias": f"SkyInfo {target} 控制", "description": "SkyInfo managed remote command schema 1",
        "mode": "queued", "max": 10,
        "fields": {
            "action": {"name": "操作", "required": True, "selector": {"select": {"options": [
                {"value": item["id"], "label": item["name"]} for item in catalog()]}}},
            "value": {"name": "数值", "required": True, "selector": {"number": {"min": 0, "max": 254, "step": 1, "mode": "box"}}},
        },
        "sequence": [{"event": "skyinfo_command", "event_data": {"target": target, "action": "{{ action }}", "value": "{{ value }}", "command_id": "skyinfo-{{ now().strftime('%Y%m%d%H%M%S%f') }}"}}],
    }


def request(base, token, path, body=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(base.rstrip("/") + path, data=data,
                                 headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=15) as response:
                raw = response.read()
                return json.loads(raw) if raw else None
        except urllib.error.HTTPError:
            raise
        except (ConnectionError, TimeoutError, urllib.error.URLError):
            if attempt == 2:
                raise
            time.sleep(0.5 * (attempt + 1))


def values(action):
    if action == "ac_control_mode":
        return [(0,"自动"),(1,"手动")]
    if action == "ac_cycle":
        return [(0,"外循环"),(1,"内循环")]
    if action == "wireless_charging":
        return [(1,"开启"),(2,"关闭")]
    if action == "steering_wheel_heat":
        return [(1,"关闭"),(2,"开启")]
    if action.startswith("seat_"):
        return [(1,"关闭"),(2,"低档"),(3,"高档"),(4,"第三档")]
    return [(0,"关闭"),(1,"开启")]


def action_config(target, item):
    action = item["id"]
    config = script_config(target)
    config["alias"] = "SkyInfo " + ("待验证 · " if item.get("validation") == "inferred" else "") + item["name"]
    config["sequence"][0]["event_data"]["action"] = action
    if action == "app_refresh":
        config["fields"] = {}
        config["sequence"][0]["event_data"]["value"] = 1
    elif "options" in item:
        options = item["options"]
        if len(options) == 1:
            config["fields"] = {}
            config["sequence"][0]["event_data"]["value"] = options[0]["value"]
        else:
            config["fields"] = {"value": {"name":item["name"],"required":True,"selector":{"select":{"options":[{"value":str(o["value"]),"label":o["label"]} for o in options]}}}}
            config["sequence"][0]["event_data"]["value"] = "{{ value | int }}"
    elif action == "ac_temperature":
        config["fields"] = {"value": {"name":"前排温度","description":"按原厂行为可能开启空调并切到自动模式。","required":True,"selector":{"number":{"min":17,"max":33,"step":1,"mode":"slider","unit_of_measurement":"°C"}}}}
    elif action == "ac_wind_level":
        config["fields"] = {"value": {"name":"风量","required":True,"selector":{"number":{"min":1,"max":7,"step":1,"mode":"slider"}}}}
    else:
        config["fields"] = {"value": {"name":item["name"],"required":True,"selector":{"select":{"options":[{"value":str(value),"label":label} for value,label in values(action) if item["min"] <= value <= item["max"]]}}}}
        config["sequence"][0]["event_data"]["value"] = "{{ value | int }}"
    return config


def deploy(base, token, target, device_id=None):
    configurations = {"skyinfo_" + target + "_command": script_config(target)}
    configurations.update({"skyinfo_" + target + "_" + item["id"]: action_config(target,item) for item in catalog()})
    for key, config in configurations.items():
        path = "/api/config/script/config/" + key
        try:
            existing = request(base, token, path)
        except urllib.error.HTTPError as error:
            if error.code != 404:
                raise RuntimeError(f"HA configuration read rejected: HTTP {error.code}") from None
            existing = None
        if existing and existing.get("description") != "SkyInfo managed remote command schema 1":
            raise RuntimeError("Existing script is not managed by SkyInfo")
        if existing != config:
            request(base, token, path, config)
    result = {"scripts": ["script." + key for key in configurations], "actions": len(catalog())}
    if device_id:
        result["label"] = label_group(base, token, target, device_id, result["scripts"])
    return result


def label_group(base, token, target, device_id, scripts):
    import websocket
    assert re.fullmatch(r"[a-f0-9]{32}", device_id)
    socket = websocket.create_connection(base.rstrip("/").replace("http", "ws", 1) + "/api/websocket", timeout=15)
    try:
        assert json.loads(socket.recv())["type"] == "auth_required"
        socket.send(json.dumps({"type": "auth", "access_token": token}))
        if json.loads(socket.recv())["type"] != "auth_ok":
            raise RuntimeError("HA authentication rejected")
        sequence = 0
        def call(kind, **data):
            nonlocal sequence
            sequence += 1
            socket.send(json.dumps(dict(id=sequence, type=kind, **data)))
            while True:
                response = json.loads(socket.recv())
                if response.get("id") == sequence:
                    if not response.get("success"):
                        raise RuntimeError("HA metadata update rejected")
                    return response["result"]
        devices = call("config/device_registry/list")
        device = next(d for d in devices if d["id"] == device_id)
        if not any(i[0] == "mqtt" and i[1].startswith("skyinfo_") for i in device.get("identifiers", [])):
            raise RuntimeError("Device is not managed by SkyInfo")
        name = "SkyInfo " + target
        labels = call("config/label_registry/list")
        label = next((v for v in labels if v["name"] == name), None)
        if label is None:
            label = call("config/label_registry/create", name=name, icon="mdi:car-info", color="amber")
        label_id = label["label_id"]
        call("config/device_registry/update", device_id=device_id, labels=sorted(set(device.get("labels", [])) | {label_id}))
        entities = call("config/entity_registry/list")
        for entity in entities:
            if entity.get("device_id") == device_id or entity["entity_id"] in scripts:
                call("config/entity_registry/update", entity_id=entity["entity_id"], labels=sorted(set(entity.get("labels", [])) | {label_id}))
        return label_id
    finally:
        socket.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--url")
    parser.add_argument("--target", required=True)
    parser.add_argument("--deploy", action="store_true")
    parser.add_argument("--device-id")
    args = parser.parse_args()
    if args.deploy:
        if not args.url:
            parser.error("--url is required when deploying")
        token = os.environ.get("SKYINFO_HA_TOKEN")
        if not token:
            raise SystemExit("Set SKYINFO_HA_TOKEN in the environment")
        print(json.dumps(deploy(args.url, token, args.target, args.device_id), ensure_ascii=False))
    else:
        print(json.dumps(script_config(args.target), ensure_ascii=False, indent=2))
