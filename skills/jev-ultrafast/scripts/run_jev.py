#!/usr/bin/env python3
"""Run Jev with an isolated local Edge browser unless a local CDP URL is supplied."""

from __future__ import annotations

import argparse
import json
import os
import platform
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from urllib.error import URLError
from urllib.parse import urlparse
from urllib.request import urlopen


def _edge_executable() -> str:
    if platform.system() == "Darwin":
        candidates = [Path("/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge")]
        candidates.append(Path.home() / "Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge")
        for candidate in candidates:
            if candidate.is_file():
                return str(candidate)
    elif platform.system() == "Windows":
        executable = shutil.which("msedge")
        if executable:
            return executable
        for variable in ("PROGRAMFILES(X86)", "PROGRAMFILES", "LOCALAPPDATA"):
            root = os.environ.get(variable)
            if root:
                candidate = Path(root) / "Microsoft/Edge/Application/msedge.exe"
                if candidate.is_file():
                    return str(candidate)
    else:
        for name in ("microsoft-edge-stable", "microsoft-edge", "msedge"):
            executable = shutil.which(name)
            if executable:
                return executable
    raise RuntimeError("Microsoft Edge is not installed at a supported path.")


def _local_endpoint(value: str) -> bool:
    parsed = urlparse(value)
    return parsed.scheme == "http" and parsed.hostname in {"127.0.0.1", "localhost", "::1"}


def _start_edge(profile: Path, headless: bool) -> subprocess.Popen[bytes]:
    return subprocess.Popen(
        [
            _edge_executable(),
            *(["--headless=new"] if headless else []),
            "--no-first-run",
            "--no-default-browser-check",
            "--remote-debugging-port=0",
            f"--user-data-dir={profile}",
            "about:blank",
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def _edge_endpoint(process: subprocess.Popen[bytes], profile: Path) -> str:
    active_port = profile / "DevToolsActivePort"
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError(f"Microsoft Edge exited during startup with code {process.returncode}.")
        try:
            port = int(active_port.read_text(encoding="utf-8").splitlines()[0])
        except (FileNotFoundError, OSError, ValueError, IndexError):
            time.sleep(0.1)
            continue
        endpoint = f"http://127.0.0.1:{port}"
        try:
            with urlopen(f"{endpoint}/json/version", timeout=3) as response:
                browser = json.load(response).get("Browser", "")
        except (OSError, URLError, json.JSONDecodeError):
            time.sleep(0.1)
            continue
        if browser.startswith("Edg/"):
            return endpoint
        raise RuntimeError(f"Expected Microsoft Edge at the local debugging endpoint, got {browser!r}.")
    raise RuntimeError("Microsoft Edge did not provide a local DevTools endpoint within 20 seconds.")


def _stop_harness(name: str) -> None:
    executable = shutil.which("browser-harness")
    if not executable:
        print("warning: browser-harness was unavailable to stop the task daemon", file=sys.stderr)
        return
    harness_env = os.environ.copy()
    harness_env.pop("BU_CDP_URL", None)
    try:
        status = subprocess.run(
            [executable, "doctor", "--json", "--require-existing-daemon"],
            env=harness_env,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=15,
        )
        daemon_alive = json.loads(status.stdout).get("daemon", {}).get("alive", False)
    except (OSError, subprocess.TimeoutExpired, json.JSONDecodeError):
        print(f"warning: could not check Browser Harness daemon {name}", file=sys.stderr)
        return
    if not daemon_alive:
        return
    try:
        result = subprocess.run(
            [executable, "--reload"],
            env=harness_env,
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=15,
        )
    except (OSError, subprocess.TimeoutExpired):
        print(f"warning: could not stop Browser Harness daemon {name}", file=sys.stderr)
    else:
        if result.returncode:
            print(f"warning: Browser Harness daemon {name} did not stop cleanly", file=sys.stderr)


def _stop_edge(process: subprocess.Popen[bytes] | None) -> None:
    if not process or process.poll() is not None:
        return
    try:
        process.terminate()
    except ProcessLookupError:
        return
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)


def _run(url: str, goal: str, headless: bool) -> int:
    typesafe_key = os.environ.get("TYPESAFE_API_KEY") or os.environ.get("TYPESAFEAI_API_KEY")
    if not typesafe_key:
        raise RuntimeError("Set TYPESAFE_API_KEY or TYPESAFEAI_API_KEY in the zsh environment.")
    os.environ["TYPESAFE_API_KEY"] = typesafe_key

    if os.environ.get("BU_CDP_WS") or os.environ.get("BU_BROWSER_ID"):
        raise RuntimeError("This runner supports local Edge CDP only; clear remote Browser Harness settings.")

    endpoint = os.environ.get("BU_CDP_URL")
    if endpoint and not _local_endpoint(endpoint):
        raise RuntimeError("BU_CDP_URL must point to a localhost Edge endpoint.")

    daemon_name = f"jev-edge-{os.getpid()}"
    previous_name = os.environ.get("BU_NAME")
    map_alias = not os.environ.get("TYPESAFE_API_KEY")
    auto_endpoint = endpoint is None
    os.environ["BU_NAME"] = daemon_name
    edge_process = None
    profile = None
    agent_context_attempted = False
    agent_context_entered = False
    try:
        if endpoint is None:
            profile = tempfile.TemporaryDirectory(prefix="jev-edge-")
            edge_process = _start_edge(Path(profile.name), headless)
            endpoint = _edge_endpoint(edge_process, Path(profile.name))
            os.environ["BU_CDP_URL"] = endpoint

        from jev_ultrafast import Agent

        agent_context_attempted = True
        with Agent(url, goal) as agent:
            agent_context_entered = True
            last_state = None
            for state in agent.run():
                last_state = state
                print(f"{state['status']} after {len(state['history'])} browser actions", flush=True)
            if last_state is None:
                raise RuntimeError("Jev ended without returning a final state.")
            observation = agent.browser.observe(screenshot=False)
            print(
                json.dumps(
                    {
                        "status": last_state["status"],
                        "url": observation["url"],
                        "title": observation["title"],
                        "visible_text": observation["text"][:4000],
                    },
                    ensure_ascii=False,
                )
            )
            return 0 if last_state["status"] == "done" else 1
    finally:
        if agent_context_attempted and not agent_context_entered:
            _stop_harness(daemon_name)
        _stop_edge(edge_process)
        if profile:
            profile.cleanup()
        if auto_endpoint:
            os.environ.pop("BU_CDP_URL", None)
        if previous_name is None:
            os.environ.pop("BU_NAME", None)
        else:
            os.environ["BU_NAME"] = previous_name
        if map_alias:
            os.environ.pop("TYPESAFE_API_KEY", None)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("url", help="Public page URL")
    parser.add_argument("goal", help="One concrete browser goal")
    parser.add_argument(
        "--headless",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Run the launched Edge headless (default); --no-headless shows the window. "
        "Ignored when BU_CDP_URL is set.",
    )
    arguments = parser.parse_args()
    try:
        return _run(arguments.url, arguments.goal, arguments.headless)
    except Exception as error:
        print(f"Jev run failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
