#!/usr/bin/env python3
"""Import the project, then run the headless simulation tests."""
from godot import run

TESTS = (("sim_test", "SIM_PASS", 300), ("wood_contacts", "WOOD_CONTACTS_PASS", 30),
         ("planting", "PLANTING_PASS", 30))

if __name__ == "__main__":
    run(["--headless", "--editor", "--import"], timeout=300)
    for script, marker, limit in TESTS:
        output = run(["--headless", "--fixed-fps", "60", "--script", "res://tests/" + script + ".gd"], timeout=limit)
        if marker not in output:
            raise RuntimeError(script + " did not finish")
    # The real game: crack a short jar, open the tank, then go back to the jar.
    output = run(["--headless", "--fixed-fps", "60", "--", "--homes-smoke"], timeout=300)
    if "HOMES_SMOKE_PASS" not in output:
        raise RuntimeError("homes smoke test did not pass")
    print("CHECK_PASS")
