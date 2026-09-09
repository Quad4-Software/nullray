# SPDX-License-Identifier: 0BSD
"""Terminal-Bench adapter for nullray print mode.

Copy this file into the temp adapter dir (see README.md) or set PYTHONPATH to
scripts/terminal-bench when the harness can import from the repo path.
"""

from __future__ import annotations

import os
import shlex
import subprocess
import tempfile
from pathlib import Path

from terminal_bench.agents.base_agent import AgentResult, BaseAgent
from terminal_bench.terminal.tmux_session import TmuxSession


def _docker_cp(src: str, container: str, dest: str) -> None:
    subprocess.run(
        ["docker", "cp", src, f"{container}:{dest}"],
        check=True,
        capture_output=True,
        text=True,
    )


class NullrayAgent(BaseAgent):
    @staticmethod
    def name() -> str:
        return "nullray"

    def __init__(self, nullray_bin: str | None = None, **kwargs):
        super().__init__(**kwargs)
        self._nullray_bin = nullray_bin or os.environ.get("NULLRAY_BIN", "")
        self._timeout = int(os.environ.get("NULLRAY_TB_TIMEOUT", "2400"))

    def perform_task(
        self,
        instruction: str,
        session: TmuxSession,
        logging_dir: Path | None = None,
    ) -> AgentResult:
        instruction = self._render_instruction(instruction)
        host_bin = self._nullray_bin
        if not host_bin or not Path(host_bin).is_file():
            raise FileNotFoundError(
                "nullray_bin missing; pass --agent-kwarg nullray_bin=/path/to/bin/nullray"
            )

        container = session.container_name
        container_bin = "/usr/local/bin/nullray"
        _docker_cp(host_bin, container, container_bin)
        session.send_keys([f"chmod +x {shlex.quote(container_bin)}", "Enter"], block=True)

        env_lines = [
            "NULLRAY_SANDBOX=off",
            "NULLRAY_STRUCTURE=0",
            "NULLRAY_AUTO=1",
            "NULLRAY_AGENT_STEPS=300",
            "NULLRAY_MAX_TOKENS=8192",
            "NULLRAY_SHELL_TIMEOUT_MS=900000",
            "NULLRAY_STREAM=0",
            "NULLRAY_ELEVATE=deny",
            "NULLRAY_SUBAGENTS=0",
        ]
        for key in (
            "OPENROUTER_API_KEY",
            "OPENAI_API_KEY",
            "NULLRAY_PROVIDER",
            "NULLRAY_MODEL",
            "NULLRAY_RAG",
            "NULLRAY_EMBED_PROVIDER",
            "NULLRAY_EMBED_MODEL",
        ):
            val = os.environ.get(key)
            if val:
                env_lines.append(f"{key}={shlex.quote(val)}")

        with tempfile.NamedTemporaryFile("w", delete=False, suffix=".env") as fh:
            fh.write("\n".join(env_lines) + "\n")
            env_host = fh.name
        prompt_host = None
        try:
            _docker_cp(env_host, container, "/tmp/nullray.env")
            with tempfile.NamedTemporaryFile("w", delete=False, suffix=".txt") as ph:
                ph.write(instruction)
                prompt_host = ph.name
            _docker_cp(prompt_host, container, "/tmp/nullray_prompt.txt")
        finally:
            os.unlink(env_host)
            if prompt_host:
                os.unlink(prompt_host)

        # Read prompt from file so shell quoting stays safe.
        cmd = (
            "set -a && . /tmp/nullray.env && set +a && "
            f"{shlex.quote(container_bin)} --print --bare --no-subagents "
            "--mode edit --perms yolo --auto --print-strict "
            "--workspace /app \"$(cat /tmp/nullray_prompt.txt)\""
        )
        session.send_keys([cmd, "Enter"], block=True, min_timeout_sec=float(self._timeout))

        if logging_dir is not None:
            logging_dir.mkdir(parents=True, exist_ok=True)
            (logging_dir / "nullray_agent.txt").write_text(
                f"bin={host_bin}\ntimeout={self._timeout}\ncontainer={container}\n",
                encoding="utf-8",
            )

        return AgentResult(total_input_tokens=0, total_output_tokens=0)
