#!/usr/bin/env python3
"""Run the installed Debug app's photo text regression on a simulator."""
import argparse
import os
from pathlib import Path
import signal
import subprocess
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--device", required=True, help="Dedicated, booted simulator UDID")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    peak = 0
    app_pids = set()
    with args.output.open("w") as log:
        process = subprocess.Popen([
            "xcrun", "simctl", "launch", "--terminate-running-process", "--console",
            args.device, "com.spektrafilm.ios", "--text-self-test"
        ], stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        deadline = time.monotonic() + 90
        try:
            while process.poll() is None:
                listing = subprocess.run(["ps", "-axo", "pid=,command="],
                                         capture_output=True, text=True, timeout=5, check=True)
                for line in listing.stdout.splitlines():
                    # Only this installed app on the requested simulator, never Simulator
                    # or another app/test running on the user's other devices.
                    if (args.device in line and "/LiteFilm.app/LiteFilm " in line
                            and "--text-self-test" in line):
                        app_pids.add(int(line.split()[0]))
                count = 0
                if app_pids:
                    threads = subprocess.run(["ps", "-M", "-p", ",".join(map(str, app_pids))],
                                             capture_output=True, text=True, timeout=5)
                    pid_text = set(map(str, app_pids))
                    # macOS omits USER on continuation thread rows: PID moves from
                    # the second whitespace-delimited field to the first.
                    count = sum(bool(parts := row.split())
                                and (parts[0] in pid_text or (len(parts) > 1 and parts[1] in pid_text))
                                for row in threads.stdout.splitlines())
                peak = max(peak, count)
                if count > 96 or time.monotonic() > deadline:
                    raise RuntimeError(f"Text test watchdog: threads={count}, timeout=90s")
                time.sleep(0.1)
        finally:
            if process.poll() is None:
                # The simulator app is launched by launchd, outside simctl's process group.
                subprocess.run(["xcrun", "simctl", "terminate", args.device, "com.spektrafilm.ios"],
                               capture_output=True, timeout=10)
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=5)
    output = args.output.read_text()
    print(output)
    if process.returncode or "LITEFILM_TEXT_SELFTEST_OK" not in output or peak == 0:
        raise RuntimeError(f"Text test failed or thread measurement unavailable (peak={peak})")
    with args.output.open("a") as log:
        log.write(f"\nPASS: app peak sampled threads={peak}, ceiling=96, timeout=90s\n")
    print(f"PASS: app peak sampled threads={peak}, ceiling=96, timeout=90s")


if __name__ == "__main__":
    main()
