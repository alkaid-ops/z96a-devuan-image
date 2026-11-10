#!/usr/bin/env python3
"""Measure LXQt desktop cost/responsiveness with and without a compositor."""
import json
import os
import re
import signal
import socket
import subprocess
import sys
import time

DISPLAY = ":0.0"
ENV = os.environ.copy()
ENV["DISPLAY"] = DISPLAY
ENV["XAUTHORITY"] = "/home/user/.Xauthority"
HZ = os.sysconf("SC_CLK_TCK")


def run(cmd, **kw):
    return subprocess.run(cmd, env=ENV, text=True, capture_output=True, **kw)


def pids(names):
    found = {}
    for name in names:
        out = run(["pgrep", "-x", name]).stdout.split()
        if not out:
            out = run(["pgrep", "-f", name]).stdout.split()
        found[name] = [int(p) for p in out[:2]]
    return found


def proc_cpu(pid):
    try:
        with open(f"/proc/{pid}/stat") as f:
            parts = f.read().split()
        return int(parts[13]) + int(parts[14])
    except OSError:
        return None


def cpu_snapshot(pmap):
    snap = {}
    for name, plist in pmap.items():
        total = 0
        for pid in plist:
            v = proc_cpu(pid)
            if v is not None:
                total += v
        snap[name] = total
    return snap


def mem_available_kb():
    with open("/proc/meminfo") as f:
        for line in f:
            if line.startswith("MemAvailable:"):
                return int(line.split()[1])
    return 0


def pss_kb(pid):
    try:
        with open(f"/proc/{pid}/smaps_rollup") as f:
            for line in f:
                if line.startswith("Pss:"):
                    return int(line.split()[1])
    except OSError:
        pass
    return 0


def gpu_residency():
    """Parse panfrost devfreq trans_stat into {freq_hz: accumulated_ms}."""
    path = "/sys/class/devfreq/fde60000.gpu/trans_stat"
    out = {}
    try:
        lines = open(path).read().splitlines()
    except OSError:
        return out
    for line in lines[2:]:
        m = re.match(r"\s*\*?\s*(\d+):", line)
        if not m:
            continue
        freq = int(m.group(1))
        tail = line.split()[-1]
        try:
            out[freq] = int(tail)
        except ValueError:
            pass
    return out


def gpu_delta(before, after):
    delta = {}
    for freq, t in after.items():
        d = t - before.get(freq, t)
        if d > 0:
            delta[freq] = d
    total = sum(delta.values())
    if not total:
        return {"total_ms": 0, "avg_mhz": None, "buckets": {}}
    avg = sum(f * d for f, d in delta.items()) / total / 1e6
    return {
        "total_ms": total,
        "avg_mhz": round(avg, 1),
        "buckets": {str(f // 1000000): round(d / total * 100, 1) for f, d in sorted(delta.items())},
    }


def launch_latency(samples=5):
    times = []
    for _ in range(samples):
        run(["pkill", "-x", "qterminal"])
        time.sleep(0.4)
        t0 = time.perf_counter()
        proc = subprocess.Popen(["qterminal"], env=ENV,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            res = subprocess.run(["xdotool", "search", "--sync", "--onlyvisible",
                                  "--class", "qterminal"],
                                 env=ENV, timeout=10, capture_output=True)
            if res.returncode == 0:
                times.append((time.perf_counter() - t0) * 1000)
        except subprocess.TimeoutExpired:
            pass
        run(["pkill", "-x", "qterminal"])
        time.sleep(0.3)
    return [round(t, 1) for t in times]


MENU_RE = re.compile(r'lxqt-panel".*?\s(\d+)x(\d+)\+')


def menu_latency(samples=5):
    times = []
    for _ in range(samples):
        run(["xdotool", "key", "Escape"])
        time.sleep(0.3)
        t0 = time.perf_counter()
        run(["xdotool", "key", "alt+F1"])
        found = False
        while time.perf_counter() - t0 < 3:
            tree = run(["xwininfo", "-root", "-tree"]).stdout
            for m in MENU_RE.finditer(tree):
                w, h = int(m.group(1)), int(m.group(2))
                if w < 700 and h > 200:
                    found = True
                    break
            if found:
                times.append((time.perf_counter() - t0) * 1000)
                break
            time.sleep(0.01)
        run(["xdotool", "key", "Escape"])
        time.sleep(0.3)
    return [round(t, 1) for t in times]


def x11perf(test, field):
    out = run(["x11perf", test]).stdout
    vals = re.findall(r"\(\s*([0-9.]+)/sec\)", out)
    return float(vals[-1]) if vals else None


VIDEO = "/home/user/Test Jellyfin 4K HEVC 8bit 60M.mp4"


def video_bench(seconds=10):
    sockpath = "/tmp/z96a-mpv.sock"
    try:
        os.unlink(sockpath)
    except FileNotFoundError:
        pass
    cmd = ["mpv", VIDEO, "--no-audio", f"--length={seconds}", "--really-quiet",
           "--input-ipc-server=" + sockpath, "--vo=gpu", "--gpu-context=x11egl",
           "--hwdec=v4l2request", "--gpu-dumb-mode=yes", "--dither=no", "--fs"]
    proc = subprocess.Popen(cmd, env=ENV, stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL)
    # wait for socket
    for _ in range(100):
        if os.path.exists(sockpath):
            break
        time.sleep(0.05)
    time.sleep(3)
    gpu0 = gpu_residency()
    mpv_cpu0 = proc_cpu(proc.pid)
    t0 = time.time()
    time.sleep(max(1, seconds - 4))
    elapsed = time.time() - t0
    mpv_cpu1 = proc_cpu(proc.pid)
    gpu1 = gpu_residency()
    props = {}
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect(sockpath)
        for p in ("frame-drop-count", "decoder-frame-drop-count",
                  "mistimed-frame-count", "playback-time", "estimated-vf-fps"):
            s.send((json.dumps({"command": ["get_property", p]}) + "\n").encode())
            buf = b""
            while b"\n" not in buf:
                buf += s.recv(4096)
            data = json.loads(buf.decode().splitlines()[0])
            props[p] = data.get("data")
        s.send((json.dumps({"command": ["quit"]}) + "\n").encode())
        s.close()
    except OSError:
        pass
    try:
        proc.wait(timeout=8)
    except subprocess.TimeoutExpired:
        proc.kill()
    run(["pkill", "-x", "mpv"])
    cpu = None
    if mpv_cpu0 is not None and mpv_cpu1 is not None and elapsed > 0:
        cpu = round((mpv_cpu1 - mpv_cpu0) / HZ / elapsed * 100, 1)
    return {
        "mpv_cpu_pct": cpu,
        "gpu": gpu_delta(gpu0, gpu1),
        "props": props,
    }


def main():
    mode = sys.argv[1]
    names = ["Xorg", "lxqt-panel", "pcmanfm-qt", "picom"]
    pmap = pids(names)

    # idle CPU over 15s
    cpu0 = cpu_snapshot(pmap)
    gpu0 = gpu_residency()
    mem0 = mem_available_kb()
    pss0 = {(n): sum(pss_kb(p) for p in pl) for n, pl in pmap.items()}
    t0 = time.time()
    time.sleep(15)
    dt = time.time() - t0
    cpu1 = cpu_snapshot(pmap)
    gpu1 = gpu_residency()
    mem1 = mem_available_kb()
    idle_cpu = {}
    for name in pmap:
        d = cpu1[name] - cpu0[name]
        idle_cpu[name] = round(d / HZ / dt * 100, 2) if d else 0.0

    result = {
        "mode": mode,
        "idle_cpu_pct": idle_cpu,
        "idle_pss_kb": pss0,
        "mem_available_after_kb": mem1,
        "mem_available_delta_kb": mem0 - mem1,
        "gpu_idle": gpu_delta(gpu0, gpu1),
        "launch_ms": launch_latency(),
        "menu_ms": menu_latency(),
        "x11perf_scroll500": x11perf("-scroll500", "scroll"),
        "x11perf_copywinwin500": x11perf("-copywinwin500", "copy"),
        "video": video_bench(),
    }
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
