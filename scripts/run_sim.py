#!/usr/bin/env python3
"""Run the synchronous FIFO SystemVerilog regression in Vivado xsim."""

import argparse
from datetime import datetime, timezone
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
LOGS = BUILD / "logs"
SOURCE_FILELIST = ROOT / "tb" / "sync" / "filelist.f"
SWEEP = [(depth, dataw) for depth in (2, 3, 8, 16) for dataw in (1, 8, 32)]
TESTS = {
    "reset",
    "fill_to_full",
    "drain_to_empty",
    "overflow_attempt",
    "underflow_attempt",
    "simul_rw_mid",
    "simul_rw_full",
    "simul_rw_empty",
    "wraparound",
    "random_balanced",
    "random_write_heavy",
    "random_read_heavy",
    "reset_mid_traffic",
}
FAIL_RE = re.compile(
    r"TEST FAILED|COVERAGE HOLE|assert(?:ion)?\s+(?:fail|error|violated)|%Error|FATAL|^ERROR:",
    re.IGNORECASE | re.MULTILINE,
)


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seeds", type=int, default=20,
                        help="number of seeds per configuration (default: 20)")
    parser.add_argument("--seed", type=int,
                        help="run exactly one seed (useful for replay)")
    parser.add_argument("--test", default="all",
                        help="one test name or all (default: all)")
    parser.add_argument("--depth", type=int,
                        help="FIFO depth for a single configuration (default: 8)")
    parser.add_argument("--dataw", type=int,
                        help="FIFO width for a single configuration (default: 8)")
    parser.add_argument("--sweep", action="store_true",
                        help="run DEPTH={2,3,8,16} x DATAW={1,8,32}")
    parser.add_argument("--timeout", type=int, default=300,
                        help="timeout in seconds for each tool invocation")
    args = parser.parse_args()
    if args.seeds < 1:
        parser.error("--seeds must be at least 1")
    if args.seed is not None and args.seed < 0:
        parser.error("--seed must be non-negative")
    if args.timeout < 1:
        parser.error("--timeout must be at least 1")
    if args.depth is not None and args.depth < 2:
        parser.error("--depth must be >= 2")
    if args.dataw is not None and args.dataw < 1:
        parser.error("--dataw must be >= 1")
    if args.sweep and (args.depth is not None or args.dataw is not None):
        parser.error("--sweep cannot be combined with --depth or --dataw")
    if args.test != "all" and args.test not in TESTS:
        parser.error(f"unknown test {args.test!r}; choose from: {', '.join(sorted(TESTS))}")
    return args


def find_tool(name):
    executable = shutil.which(name)
    if executable is None:
        raise RuntimeError(
            f"'{name}' was not found on PATH. Install/configure the selected "
            "simulator and try again."
        )
    return executable


def run_command(command, log_path, timeout):
    if os.name == "nt" and Path(command[0]).suffix.lower() in {".bat", ".cmd"}:
        rendered = []
        for index, value in enumerate(command):
            argument = str(value)
            if index and command[index - 1] in {"-generic_top", "-testplusarg"}:
                # Vivado's Windows batch launcher splits these assignments at '='.
                rendered.append(f'"{argument}"')
            elif any(char.isspace() for char in argument) or '"' in argument:
                rendered.append('"' + argument.replace('"', '""') + '"')
            else:
                rendered.append(argument)
        command_line = " ".join(rendered)
        command = (
            f'"{os.environ.get("COMSPEC", "cmd.exe")}" '
            f'/d /s /c "{command_line}"'
        )

    try:
        result = subprocess.run(
            command,
            cwd=BUILD,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
        output = result.stdout + result.stderr
        log_path.write_text(output, encoding="utf-8")
        return result.returncode, output
    except subprocess.TimeoutExpired as exc:
        output = (exc.stdout or "") + (exc.stderr or "")
        if isinstance(output, bytes):
            output = output.decode(errors="replace")
        output += f"\nERROR: command timed out after {timeout} seconds\n"
        log_path.write_text(output, encoding="utf-8")
        return 124, output


def resolve_filelist():
    files = []
    for entry in SOURCE_FILELIST.read_text(encoding="utf-8").splitlines():
        entry = entry.strip()
        if entry and not entry.startswith("#"):
            source = (ROOT / entry).resolve()
            if not source.is_file():
                raise RuntimeError(f"source listed in filelist does not exist: {source}")
            files.append(str(source).replace("\\", "/"))
    generated = BUILD / "filelist.f"
    generated.write_text("\n".join(files) + "\n", encoding="utf-8")
    return generated


def compile_xsim(depth, dataw, tag, filelist, timeout):
    xvlog = find_tool("xvlog")
    xelab = find_tool("xelab")
    compile_log = LOGS / f"{tag}_xvlog.log"
    code, output = run_command(
        [xvlog, "-sv", "-f", str(filelist)],
        compile_log,
        timeout,
    )
    if code != 0 or FAIL_RE.search(output):
        return None, f"xvlog failed; see {compile_log.relative_to(ROOT)}"

    snapshot = f"sync_fifo_d{depth}_w{dataw}"
    elab_log = LOGS / f"{tag}_xelab.log"
    code, output = run_command(
        [
            xelab,
            "work.sync_fifo_tb",
            "-s",
            snapshot,
            "-generic_top",
            f"DEPTH={depth}",
            "-generic_top",
            f"DATAW={dataw}",
            "--debug",
            "typical",
        ],
        elab_log,
        timeout,
    )
    if code != 0 or FAIL_RE.search(output):
        return None, f"xelab failed; see {elab_log.relative_to(ROOT)}"
    return snapshot, None


def run_xsim(snapshot, seed, test, log_path, timeout):
    xsim = find_tool("xsim")
    return run_command(
        [
            xsim,
            snapshot,
            "-testplusarg",
            f"seed={seed}",
            "-testplusarg",
            f"test={test}",
            "-runall",
        ],
        log_path,
        timeout,
    )


def write_results(args, configurations, results, fatal_error=None):
    report = ROOT / "docs" / "results.md"
    report.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "# Regression results",
        "",
        f"- Generated: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}",
        "- Simulator: Vivado xsim",
        f"- Test selection: `{args.test}`",
        f"- Configurations: {len(configurations)}",
        f"- Seeds per configuration: {1 if args.seed is not None else args.seeds}",
        "",
        "| DEPTH | DATAW | Seed | Result | Log |",
        "|------:|------:|-----:|--------|-----|",
    ]
    if results:
        for result in results:
            log = f"[log](../{result['log']})" if result.get("log") else "—"
            lines.append(
                f"| {result['depth']} | {result['dataw']} | "
                f"{result.get('seed', '—')} | {result['status']} | {log} |"
            )
    else:
        for depth, dataw in configurations:
            lines.append(f"| {depth} | {dataw} | — | NOT RUN | — |")
    if fatal_error:
        lines.extend(["", f"Run error: `{fatal_error}`"])
    lines.extend(["", "The report is refreshed by `scripts/run_sim.py`."])
    report.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    args = parse_args()
    BUILD.mkdir(exist_ok=True)
    LOGS.mkdir(exist_ok=True)
    configurations = SWEEP if args.sweep else [
        (args.depth if args.depth is not None else 8,
         args.dataw if args.dataw is not None else 8)
    ]
    seeds = [args.seed] if args.seed is not None else list(range(1, args.seeds + 1))
    results = []
    fatal_error = None

    try:
        filelist = resolve_filelist()
        for depth, dataw in configurations:
            tag = f"d{depth}_w{dataw}"
            executable, compile_error = compile_xsim(
                depth, dataw, tag, filelist, args.timeout
            )
            if compile_error:
                results.append({
                    "depth": depth,
                    "dataw": dataw,
                    "status": "COMPILE FAIL",
                    "log": "",
                })
                print(f"DEPTH={depth} DATAW={dataw}: {compile_error}", file=sys.stderr)
                continue

            for seed in seeds:
                log_path = LOGS / f"{tag}_seed{seed}_{args.test}.log"
                started = time.monotonic()
                code, output = run_xsim(
                    executable, seed, args.test, log_path, args.timeout
                )
                passed = (
                    code == 0
                    and "TEST PASSED" in output
                    and FAIL_RE.search(output) is None
                )
                status = "PASS" if passed else "FAIL"
                results.append({
                    "depth": depth,
                    "dataw": dataw,
                    "seed": seed,
                    "status": status,
                    "log": str(log_path.relative_to(ROOT)).replace("\\", "/"),
                })
                print(
                    f"DEPTH={depth} DATAW={dataw} seed={seed}: {status} "
                    f"({time.monotonic() - started:.1f}s)"
                )
                if not passed:
                    replay = (
                        f"python scripts/run_sim.py --depth {depth} "
                        f"--dataw {dataw} --test {args.test} "
                        f"--seed {seed}"
                    )
                    print(f"  Replay: {replay}")
                    print(f"  Log: {log_path.relative_to(ROOT)}")
    except (RuntimeError, OSError) as exc:
        fatal_error = str(exc)
        print(f"ERROR: {fatal_error}", file=sys.stderr)

    write_results(args, configurations, results, fatal_error)
    expected_runs = len(configurations) * len(seeds)
    passed = sum(result["status"] == "PASS" for result in results)
    failed = expected_runs - passed
    coverage_holes = 0
    for result in results:
        if result.get("log") and (ROOT / result["log"]).exists():
            coverage_holes += len(
                re.findall(
                    r"COVERAGE HOLE",
                    (ROOT / result["log"]).read_text(encoding="utf-8", errors="replace"),
                )
            )
    print(
        f"sync_fifo regression: {len(configurations)} configs x {len(seeds)} seeds = "
        f"{passed}/{expected_runs} PASS | "
        f"coverage holes: {coverage_holes}"
    )
    print(f"Results written to {ROOT / 'docs' / 'results.md'}")
    return 1 if fatal_error or failed else 0


if __name__ == "__main__":
    sys.exit(main())
