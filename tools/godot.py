#!/usr/bin/env python3
"""Run the pinned Godot editor/game without replacing a system installation."""
import subprocess
import sys
from bootstrap import ROOT, engine


def run(arguments, timeout=None):
    importing = "--import" in arguments
    if importing:
        arguments = [arg for arg in arguments if arg not in ("--import", "--quit")]
        arguments += ["--quit-after", "120", "--max-fps", "60"]
    markers = ("SCRIPT ERROR:", "ERROR:", "Parse Error:", "TEST FAIL")
    for attempt in (1, 2):
        result = subprocess.run([str(engine()), "--path", str(ROOT), *arguments],
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=timeout)
        print(result.stdout, end="", flush=True)
        reported = any(marker in result.stdout for marker in markers)
        # The headless editor occasionally dies on exit after a clean import
        # with no message at all. That one case is retried once; anything that
        # reports an error fails immediately.
        if importing and attempt == 1 and result.returncode and not reported:
            print("Godot exited with code %d during import without reporting an error; retrying once." % result.returncode, flush=True)
            continue
        break
    if result.returncode or reported:
        raise RuntimeError("Godot failed (exit code %d); see output above" % result.returncode)
    return result.stdout


if __name__ == "__main__":
    raise SystemExit(subprocess.call([str(engine()), "--path", str(ROOT), *sys.argv[1:]]))
