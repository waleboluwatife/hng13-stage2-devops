import os
import time
import requests
from collections import deque
import re
import sys
import json
import datetime

LOG_PATH = "/var/log/nginx/access_stage3.log"

SLACK_WEBHOOK_URL = os.getenv("SLACK_WEBHOOK_URL", "")
ERROR_RATE_THRESHOLD = float(os.getenv("ERROR_RATE_THRESHOLD", "2"))  # percent
WINDOW_SIZE = int(os.getenv("WINDOW_SIZE", "200"))
ALERT_COOLDOWN_SEC = int(os.getenv("ALERT_COOLDOWN_SEC", "300"))

# last alert times
last_failover_alert_ts = 0
last_error_alert_ts = 0

# remember last seen pool
last_pool = os.getenv("ACTIVE_POOL", "blue")

# rolling window of recent requests: True=error, False=ok
recent = deque(maxlen=WINDOW_SIZE)

line_re = re.compile(
    r'.*pool=(?P<pool>\S+)\s+release=(?P<release>\S+)\s+status=(?P<status>\d+)\s+upstream_status=(?P<upstream_status>\d+)\s+upstream_addr=(?P<upstream_addr>\S+)'
)

def send_slack(text: str):
    if not SLACK_WEBHOOK_URL:
        return
    try:
        requests.post(
            SLACK_WEBHOOK_URL,
            data=json.dumps({"text": text}),
            headers={"Content-Type": "application/json"},
            timeout=5,
        )
    except Exception:
        pass

def maybe_alert_failover(pool_now):
    global last_pool, last_failover_alert_ts
    now = time.time()
    if pool_now != last_pool:
        # pool changed
        if now - last_failover_alert_ts >= ALERT_COOLDOWN_SEC:
            send_slack(f":rotating_light: Failover detected😒: {last_pool} -> {pool_now} at {datetime.datetime.utcnow().isoformat()}Z")
            last_failover_alert_ts = now
        last_pool = pool_now

def maybe_alert_error_rate():
    global last_error_alert_ts
    now = time.time()

    if len(recent) == 0:
        return

    err_count = sum(1 for x in recent if x)
    rate = (err_count / len(recent)) * 100.0

    if rate >= ERROR_RATE_THRESHOLD:
        if now - last_error_alert_ts >= ALERT_COOLDOWN_SEC:
            send_slack(f":warning: High upstream error rate🤦‍♂️ {rate:.2f}% over last {len(recent)} requests at {datetime.datetime.utcnow().isoformat()}Z")
            last_error_alert_ts = now

def tail_file(path):
    with open(path, "r") as f:
        # jump to end
        f.seek(0, 2)
        while True:
            line = f.readline()
            if not line:
                time.sleep(0.2)
                continue
            yield line.strip()

def main():
    global recent
    for line in tail_file(LOG_PATH):
        m = line_re.match(line)
        if not m:
            continue

        pool_now = m.group("pool")
        upstream_status = m.group("upstream_status")

        # upstream_status is status from blue/green. Treat 5xx as error.
        is_error = upstream_status.startswith("5")

        recent.append(is_error)

        maybe_alert_failover(pool_now)
        maybe_alert_error_rate()

if __name__ == "__main__":
    main()
