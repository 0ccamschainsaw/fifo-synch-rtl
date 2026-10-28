#!/usr/bin/env python3
"""
run_sim.py - run every RV32I test in Vivado's xsim WITHOUT opening the GUI.

Two kinds of test are run:
  1. LEGACY testbenches  sim/tb_*.v  (programs hard-coded inside the testbench).
     Listed in TESTS below. These are untouched.
  2. HEX tests           tests/<name>.hex + tests/<name>.exp
     One generic testbench (sim/tb_generic.v) loads the program through the CPU's
     instruction-memory write port and checks the results listed in the .exp file.
     They are discovered automatically: drop in a new pair of files, no edits here.
     A test whose name starts with "xfail_" is a KNOWN failure: it is reported as
     XFAIL and does not count against the exit code (XPASS, an unexpected pass, does).

Usage (from the repo root, in a terminal where Vivado's tools are on PATH):
    python scripts\\run_sim.py                  run everything
    python scripts\\run_sim.py --test tb_program1   run one legacy testbench
    python scripts\\run_sim.py --test prog1         run one hex test
    python scripts\\run_sim.py --wave           also save waveforms (.wdb)
    python scripts\\run_sim.py --clean          delete sim_out/ first
    python scripts\\run_sim.py --timeout 300    seconds allowed per step

Exit code: 0 if every counted test passed, 1 otherwise.
"""
import argparse   #parse command-line arguments
import re         #regular expressions for parsing xsim output
import shutil     #file operations (copy, delete)
import torch      #for tensor operations (used in the testbench)
import subprocess #run vivado cmds
import sys        #error reporting and exit
import time       #time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent   # the repo folder
OUT = ROOT / "sim_out"                           # all generated files go here
HEX_DIR = ROOT / "tests"                         # *.hex programs + *.exp expectations

# LEGACY testbench MODULES (the word after "module" in each sim/tb_*.v file)
TESTS = ["tb_program1", "tb_program2", "tb_program3_fibonacci"]
GENERIC_TB = "tb_generic"                        # module in sim/tb_generic.v

# What the script looks for in a simulation's output
PASS_RE = re.compile(r"TEST PASSED")
FAIL_RE = re.compile(r"TEST FAILED|FATAL|\bERROR\b")


def tool(name):
    """Find a Vivado command (xvlog / xelab / xsim) on PATH, or stop with a hint."""
    path = shutil.which(name)  # on Windows this also finds xvlog.bat
    if not path:
        sys.exit(f"ERROR: '{name}' not found. Run Vivado's settings64.bat first "
                 f"(see README, Step 4).")
    return path


def run(cmd, logname, timeout):
    """Run a command inside sim_out/, save its output to a log file, return (code, text)."""
    result = subprocess.run(cmd, cwd=OUT, capture_output=True, text=True,
                            timeout=timeout)
    text = result.stdout + result.stderr
    (OUT / logname).write_text(text)
    return result.returncode, text


def build_jobs():
    """Every test as a dict: name (what you pass to --test), tb module, plusargs."""
    jobs = [{"name": tb, "tb": tb, "xfail": False} for tb in TESTS]
    for hexf in sorted(HEX_DIR.glob("*.hex")):
        exp = hexf.with_suffix(".exp")
        jobs.append({
            "name": hexf.stem,
            "tb": GENERIC_TB,
            # forward slashes: safe for xsim on Windows, and $readmemh accepts them
            "hex": hexf, "exp": exp,
            "xfail": hexf.stem.startswith("xfail_"),
            "missing_exp": not exp.exists(),
        })
    return jobs


def main():
    ap = argparse.ArgumentParser(description="Run RV32I tests in Vivado xsim.")
    ap.add_argument("--test", help="run only this test (a legacy testbench module "
                                   "or a hex-test name such as prog1)")
    ap.add_argument("--wave", action="store_true", help="save waveforms (.wdb)")
    ap.add_argument("--timeout", type=int, default=120,
                    help="seconds allowed per step (default 120)")
    ap.add_argument("--clean", action="store_true", help="delete sim_out/ first")
    args = ap.parse_args()

    if args.clean:
        shutil.rmtree(OUT, ignore_errors=True)
    OUT.mkdir(exist_ok=True)

    jobs = build_jobs()
    if args.test:
        jobs = [j for j in jobs if j["name"] == args.test]
        if not jobs:
            names = ", ".join(j["name"] for j in build_jobs())
            sys.exit(f"ERROR: no test named '{args.test}'. Available: {names}")

    # 1) COMPILE every .v file in rtl/ and sim/
    sources = sorted((ROOT / "rtl").glob("*.v")) + sorted((ROOT / "sim").glob("*.v"))
    print(f"Compiling {len(sources)} Verilog files...")
    code, text = run([tool("xvlog")] + [str(p) for p in sources],
                     "compile.log", args.timeout)
    if code != 0 or "ERROR" in text:
        print(text)
        sys.exit("Compile failed. Details are in sim_out/compile.log")

    # 2) For each test: ELABORATE (once per testbench module), then SIMULATE
    details = {}        # test name -> first few error lines from its log
    snapshots = {}      # tb module -> snapshot name, or None if elaboration failed
    results = []
    for job in jobs:
        name, tb = job["name"], job["tb"]
        print(f"Running {name}...")
        start = time.time()

        if job.get("missing_exp"):
            results.append((name, "NO .EXP", time.time() - start))
            continue

        if tb not in snapshots:
            snap = f"snap_{tb}"
            code, _ = run([tool("xelab"), f"work.{tb}", "-s", snap, "--debug", "typical"],
                          f"{tb}_elab.log", args.timeout)
            snapshots[tb] = snap if code == 0 else None
        snap = snapshots[tb]
        if snap is None:
            results.append((name, "ELAB FAIL", time.time() - start))
            continue

        # hex tests: put this test's files where tb_generic looks for them
        # (no plusargs: xsim.bat splits arguments on '=', which breaks them)
        if "hex" in job:
            shutil.copyfile(job["hex"], OUT / "test.hex")
            shutil.copyfile(job["exp"], OUT / "test.exp")

        # a tiny Tcl script that tells xsim what to do
        tcl = OUT / f"{name}.tcl"
        tcl.write_text(("log_wave -r /*\n" if args.wave else "") + "run all\nquit\n")

        cmd = [tool("xsim"), snap, "-tclbatch", tcl.name, "-log", f"{name}.log"]
        if args.wave:
            cmd += ["-wdb", f"{name}.wdb"]
        try:
            code, text = run(cmd, f"{name}_stdout.log", args.timeout)
            ok = bool(PASS_RE.search(text)) and not FAIL_RE.search(text)
            if job["xfail"]:
                # XFAIL only if the TESTBENCH reported failure; a tool crash is a FAIL
                status = "XPASS" if ok else ("XFAIL" if "TEST FAILED" in text else "FAIL")
            else:
                status = "PASS" if ok else "FAIL"
            if not ok:
                details[name] = [l.strip() for l in text.splitlines()
                                 if FAIL_RE.search(l) or "Expected a switch" in l][:5]
        except subprocess.TimeoutExpired:
            status = "TIMEOUT"
        results.append((name, status, time.time() - start))

    # 3) SUMMARY  (XFAIL = expected failure: shown, but not counted)
    print(f"\n{'test':<28}{'result':<12}{'time (s)':>8}")
    print("-" * 48)
    for name, status, secs in results:
        print(f"{name:<28}{status:<12}{secs:>8.1f}")
    xfails = [r for r in results if r[1] == "XFAIL"]
    counted = [r for r in results if r[1] != "XFAIL"]
    failed = [r for r in counted if r[1] != "PASS"]
    line = f"\n{len(counted) - len(failed)}/{len(counted)} passed"
    if xfails:
        line += f", {len(xfails)} expected failure(s) (XFAIL)"
    print(line)
    for name, status, _ in failed:
        print(f"  -> look at sim_out/{name}_stdout.log  ({status})")
        for l in details.get(name, []):
            print(f"       {l}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()