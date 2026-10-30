#!/usr/bin/python3
"""Deterministic sign-in lifecycle tests. No network or credentials."""
import pathlib
import sys
import time

name = pathlib.Path(sys.argv[0]).stem
args = sys.argv[1:]
assert args in (["login"], ["login", "status"], ["auth", "login", "--claudeai"], ["auth", "status"]), args
if name == "denied":
    sys.exit(1)
if name == "waiting":
    time.sleep(30)
sys.exit(0)
