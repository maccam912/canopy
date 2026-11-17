#!/usr/bin/env python3
"""Import the project, then run the headless simulation tests."""
from godot import run

TESTS = (("sim_test", "SIM_PASS", 300),)

if __name__ == "__main__":
    run(["--headless", "--editor", "--import"], timeout=300)
    for script, marker, limit in TESTS:
        output = run(["--headless", "--fixed-fps", "60", "--script", "res://tests/" + script + ".gd"], timeout=limit)
        if marker not in output:
            raise RuntimeError(script + " did not finish")
    print("CHECK_PASS")
