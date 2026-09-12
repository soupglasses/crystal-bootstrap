#!/usr/bin/env python3
"""Run one build step and record its wall time and Linux child peak RSS."""
import json
from pathlib import Path
import resource
import subprocess
import sys
import time

report, *command = sys.argv[1:]
start = time.monotonic()
result = subprocess.run(command)
Path(report).write_text(json.dumps({
    "command": command,
    "exit_status": result.returncode,
    "wall_seconds": round(time.monotonic() - start, 3),
    "peak_rss_kib": resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss,
}, indent=2) + "\n")
sys.exit(result.returncode)
