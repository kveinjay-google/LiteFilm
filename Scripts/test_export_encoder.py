#!/usr/bin/env python3
"""Small native encoder regression, with external outputs and bounded execution."""
import argparse
import os
from pathlib import Path
import signal
import subprocess
import time


def run(command, log, timeout, thread_limit):
    peak = 0
    with log.open("w") as output:
        process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        deadline = time.monotonic() + timeout
        try:
            while process.poll() is None:
                groups = subprocess.run(["ps", "-axo", "pid=,pgid="],
                                        capture_output=True, text=True, timeout=5, check=True)
                members = {line.split()[0] for line in groups.stdout.splitlines()
                           if len(line.split()) == 2 and line.split()[1] == str(process.pid)}
                count = 0
                if members:
                    # macOS -M prints one row per thread and ignores normal -o formatting.
                    threads = subprocess.run(["ps", "-M", "-p", ",".join(members)],
                                             capture_output=True, text=True, timeout=5)
                    # Continuation thread rows omit USER, so PID is then the first field.
                    count = sum(bool(parts := line.split())
                                and (parts[0] in members or (len(parts) > 1 and parts[1] in members))
                                for line in threads.stdout.splitlines())
                peak = max(peak, count)
                if count > thread_limit or time.monotonic() > deadline:
                    raise RuntimeError(f"Resource watchdog: threads={count}, limit={thread_limit}")
                time.sleep(0.1)
            if process.returncode:
                raise RuntimeError(f"Command failed ({process.returncode}); see {log}")
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=5)
    print(log.read_text())
    if peak == 0:
        raise RuntimeError("Thread measurement unavailable; cannot certify this run")
    print(f"PASS: peak process-group threads={peak}, ceiling={thread_limit}; log={log}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True,
                        help="Output directory (use external storage on the development Mac)")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    root = Path(__file__).resolve().parents[1]
    executable = args.output / "export-tests"
    run(["xcrun", "swiftc", "-j", "1", "-module-cache-path", str(args.output / "ModuleCache"),
         str(root / "SpektraFilm/ExportEncoder.swift"), str(Path(__file__).with_suffix(".swift")),
         "-o", str(executable)], args.output / "encoder-compile.log", 90, 32)
    # ImageIO/HEIC may use Apple's codec worker threads; this is a bounded 800x600 test.
    run([str(executable)], args.output / "encoder-tests.log", 60, 96)


if __name__ == "__main__":
    main()
