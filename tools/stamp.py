#!/usr/bin/env python3
"""Stamp a build number into the project: version 0.1.N everywhere it shows."""
import argparse
import re
from bootstrap import ROOT


def stamp(build):
    version = "0.1.%d" % build
    replacements = {
        ROOT / "project.godot": [(r'config/version=".*"', 'config/version="%s"' % version)],
        ROOT / "export_presets.cfg": [
            (r"version/code=\d+", "version/code=%d" % build),
            (r'version/name=".*"', 'version/name="%s"' % version),
            (r'application/short_version=".*"', 'application/short_version="%s"' % version),
            (r'application/version=".*"', 'application/version="%d"' % build),
        ],
    }
    for path, rules in replacements.items():
        text = path.read_text()
        for pattern, value in rules:
            text, count = re.subn(pattern, value, text)
            if count == 0:
                raise RuntimeError("Nothing to stamp for %s in %s" % (pattern, path.name))
        path.write_text(text)
    return version


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("build", type=int, help="monotonically increasing build number")
    print(stamp(parser.parse_args().build))
