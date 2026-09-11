#!/usr/bin/env python3
"""Launch the CUDA game_replay PTX kernel and compare it with a CPU replay."""

import argparse
import ctypes
import json
import re
import struct
import subprocess
import tempfile
import time
from pathlib import Path


CUDA_SUCCESS = 0
CU_LIMIT_STACK_SIZE = 0
CU_LIMIT_MALLOC_HEAP_SIZE = 2


class Cuda:
    def __init__(self, device_ordinal):
        try:
            self.lib = ctypes.CDLL("libcuda.so.1")
        except OSError as exc:
            raise RuntimeError(f"cannot load libcuda.so.1: {exc}") from exc
        self._bind()
        self.call("cuInit", 0)
        device = ctypes.c_int()
        self.call("cuDeviceGet", ctypes.byref(device), device_ordinal)
        self.context = ctypes.c_void_p()
        self.call("cuDevicePrimaryCtxRetain", ctypes.byref(self.context), device)
        self.call("cuCtxSetCurrent", self.context)

    def _function(self, name, argtypes, restype=ctypes.c_int):
        fn = getattr(self.lib, name)
        fn.argtypes = argtypes
        fn.restype = restype
        return fn

    def _bind(self):
        void_p = ctypes.c_void_p
        size_t = ctypes.c_size_t
        self._function("cuInit", [ctypes.c_uint])
        self._function("cuDeviceGet", [ctypes.POINTER(ctypes.c_int), ctypes.c_int])
        self._function("cuDevicePrimaryCtxRetain", [ctypes.POINTER(void_p), ctypes.c_int])
        self._function("cuCtxSetCurrent", [void_p])
        self._function("cuCtxSetLimit", [ctypes.c_int, size_t])
        self._function("cuModuleLoadDataEx", [ctypes.POINTER(void_p), void_p, ctypes.c_uint, void_p, void_p])
        self._function("cuModuleGetFunction", [ctypes.POINTER(void_p), void_p, ctypes.c_char_p])
        self._function("cuMemAlloc_v2", [ctypes.POINTER(ctypes.c_uint64), size_t])
        self._function("cuMemFree_v2", [ctypes.c_uint64])
        self._function("cuMemsetD8_v2", [ctypes.c_uint64, ctypes.c_ubyte, size_t])
        self._function(
            "cuLaunchKernel",
            [void_p, ctypes.c_uint, ctypes.c_uint, ctypes.c_uint,
             ctypes.c_uint, ctypes.c_uint, ctypes.c_uint, ctypes.c_uint,
             void_p, ctypes.POINTER(void_p), ctypes.POINTER(void_p)],
        )
        self._function("cuCtxSynchronize", [])
        self._function("cuMemcpyDtoH_v2", [void_p, ctypes.c_uint64, size_t])
        self._function("cuGetErrorName", [ctypes.c_int, ctypes.POINTER(ctypes.c_char_p)])
        self._function("cuGetErrorString", [ctypes.c_int, ctypes.POINTER(ctypes.c_char_p)])

    def call(self, name, *args):
        result = getattr(self.lib, name)(*args)
        if result != CUDA_SUCCESS:
            error_name = ctypes.c_char_p()
            error_text = ctypes.c_char_p()
            self.lib.cuGetErrorName(result, ctypes.byref(error_name))
            self.lib.cuGetErrorString(result, ctypes.byref(error_text))
            label = error_name.value.decode() if error_name.value else f"CUDA error {result}"
            detail = error_text.value.decode() if error_text.value else "unknown error"
            raise RuntimeError(f"{name}: {label}: {detail}")

    def load_kernel(self, ptx, name):
        image = ctypes.create_string_buffer(ptx.read_bytes() + b"\0")
        module = ctypes.c_void_p()
        # Lower JIT optimization keeps this first full-engine probe within Snowball RAM.
        options = (ctypes.c_int * 1)(7)  # CU_JIT_OPTIMIZATION_LEVEL
        values = (ctypes.c_void_p * 1)(1)
        self.call("cuModuleLoadDataEx", ctypes.byref(module), ctypes.cast(image, ctypes.c_void_p), 1, options, values)
        function = ctypes.c_void_p()
        self.call("cuModuleGetFunction", ctypes.byref(function), module, name.encode())
        return image, module, function


def checked_sizes(jobs, ticks, stride, max_bytes):
    if jobs <= 0 or ticks <= 0 or stride <= 0:
        raise ValueError("jobs, ticks, and stride must be positive")
    records = jobs * ticks
    output_bytes = records * stride
    lengths_bytes = records * 8
    if output_bytes > max_bytes:
        raise ValueError(
            f"requested output is {output_bytes} bytes, above --max-bytes {max_bytes}"
        )
    return records, output_bytes, lengths_bytes


def parse_lengths(raw, records, stride):
    if len(raw) != records * 8:
        return None
    values = list(struct.unpack(f"<{records}Q", raw))
    return values if all(value <= stride for value in values) else None


def load_reference(path, records, output_bytes, stride):
    raw = path.read_bytes()
    sidecars = [
        Path(str(path) + ".lengths"),
        path.with_suffix(path.suffix + ".lengths"),
        path.with_name(path.name + ".lengths.bin"),
    ]
    for sidecar in dict.fromkeys(sidecars):
        if sidecar.exists() and len(raw) == output_bytes:
            lengths = parse_lengths(sidecar.read_bytes(), records, stride)
            if lengths is not None:
                return raw, lengths, str(sidecar)

    lengths_bytes = records * 8
    if len(raw) == output_bytes + lengths_bytes:
        prefix = parse_lengths(raw[:lengths_bytes], records, stride)
        suffix = parse_lengths(raw[output_bytes:], records, stride)
        if prefix is not None and suffix is None:
            return raw[lengths_bytes:], prefix, "length-prefix"
        if suffix is not None and prefix is None:
            return raw[:output_bytes], suffix, "length-suffix"
        if prefix is not None:
            return raw[lengths_bytes:], prefix, "length-prefix"
    raise ValueError(
        f"CPU reference {path} has {len(raw)} bytes; expected {output_bytes} data bytes "
        f"plus {lengths_bytes} length bytes, or a .lengths sidecar"
    )


def run_cpu(binary, jobs, ticks, stride, output, timeout, benchmark=False):
    command = [
        str(binary), "--jobs", str(jobs), "--ticks", str(ticks),
        "--stride", str(stride), "--out", str(output),
    ]
    if benchmark:
        command.append("--bench")
    started = time.perf_counter()
    completed = subprocess.run(command, text=True, capture_output=True, timeout=timeout)
    elapsed = time.perf_counter() - started
    if completed.returncode:
        detail = completed.stderr.strip() or completed.stdout.strip()
        raise RuntimeError(f"CPU reference exited {completed.returncode}: {detail}")
    match = re.search(r"(?:^|\s)cpu_seconds=([0-9.eE+-]+)", completed.stderr)
    compute = float(match.group(1)) if match else None
    return elapsed, compute


def run_gpu(cuda, function, jobs, ticks, stride, output_bytes, lengths_bytes):
    output_dev = ctypes.c_uint64()
    lengths_dev = ctypes.c_uint64()
    cuda.call("cuMemAlloc_v2", ctypes.byref(output_dev), output_bytes)
    try:
        cuda.call("cuMemAlloc_v2", ctypes.byref(lengths_dev), lengths_bytes)
        try:
            cuda.call("cuMemsetD8_v2", output_dev, 0, output_bytes)
            cuda.call("cuMemsetD8_v2", lengths_dev, 0, lengths_bytes)
            jobs_arg = ctypes.c_uint32(jobs)
            ticks_arg = ctypes.c_uint32(ticks)
            stride_arg = ctypes.c_uint32(stride)
            arguments = (ctypes.c_void_p * 5)(
                ctypes.cast(ctypes.byref(output_dev), ctypes.c_void_p),
                ctypes.cast(ctypes.byref(lengths_dev), ctypes.c_void_p),
                ctypes.cast(ctypes.byref(jobs_arg), ctypes.c_void_p),
                ctypes.cast(ctypes.byref(ticks_arg), ctypes.c_void_p),
                ctypes.cast(ctypes.byref(stride_arg), ctypes.c_void_p),
            )
            started = time.perf_counter()
            cuda.call(
                "cuLaunchKernel", function, (jobs + 31) // 32, 1, 1, 32, 1, 1,
                0, None, arguments, None,
            )
            cuda.call("cuCtxSynchronize")
            kernel_elapsed = time.perf_counter() - started
            output = ctypes.create_string_buffer(output_bytes)
            lengths = (ctypes.c_uint64 * (lengths_bytes // 8))()
            copy_started = time.perf_counter()
            cuda.call("cuMemcpyDtoH_v2", output, output_dev, output_bytes)
            cuda.call("cuMemcpyDtoH_v2", lengths, lengths_dev, lengths_bytes)
            copy_elapsed = time.perf_counter() - copy_started
            return output.raw, list(lengths), kernel_elapsed, copy_elapsed
        finally:
            cuda.call("cuMemFree_v2", lengths_dev)
    finally:
        cuda.call("cuMemFree_v2", output_dev)


def run_gpu_benchmark(cuda, function, jobs, ticks):
    output_bytes = jobs * 8
    output_dev = ctypes.c_uint64()
    cuda.call("cuMemAlloc_v2", ctypes.byref(output_dev), output_bytes)
    try:
        jobs_arg = ctypes.c_uint32(jobs)
        ticks_arg = ctypes.c_uint32(ticks)
        arguments = (ctypes.c_void_p * 3)(
            ctypes.cast(ctypes.byref(output_dev), ctypes.c_void_p),
            ctypes.cast(ctypes.byref(jobs_arg), ctypes.c_void_p),
            ctypes.cast(ctypes.byref(ticks_arg), ctypes.c_void_p),
        )

        def launch():
            cuda.call(
                "cuLaunchKernel", function, (jobs + 31) // 32, 1, 1, 32, 1, 1,
                0, None, arguments, None,
            )
            cuda.call("cuCtxSynchronize")

        cuda.call("cuMemsetD8_v2", output_dev, 0, output_bytes)
        launch()  # Exclude CUDA context setup and PTX JIT from the measurement.
        cuda.call("cuMemsetD8_v2", output_dev, 0, output_bytes)
        started = time.perf_counter()
        launch()
        kernel_elapsed = time.perf_counter() - started
        output = ctypes.create_string_buffer(output_bytes)
        copy_started = time.perf_counter()
        cuda.call("cuMemcpyDtoH_v2", output, output_dev, output_bytes)
        copy_elapsed = time.perf_counter() - copy_started
        return output.raw, kernel_elapsed, copy_elapsed
    finally:
        cuda.call("cuMemFree_v2", output_dev)


def compare(cpu_data, cpu_lengths, gpu_data, gpu_lengths, jobs, ticks, stride):
    for job in range(jobs):
        for tick in range(ticks):
            record = job * ticks + tick
            cpu_len = cpu_lengths[record]
            gpu_len = gpu_lengths[record]
            if cpu_len != gpu_len:
                return {"job": job, "tick": tick, "kind": "length", "cpu": cpu_len, "gpu": gpu_len}
            start = record * stride
            expected = cpu_data[start:start + cpu_len]
            actual = gpu_data[start:start + gpu_len]
            if expected != actual:
                offset = next(i for i, pair in enumerate(zip(expected, actual)) if pair[0] != pair[1])
                left = max(0, offset - 8)
                right = min(cpu_len, offset + 9)
                return {
                    "job": job, "tick": tick, "kind": "byte", "offset": offset,
                    "cpu": expected[offset], "gpu": actual[offset],
                    "cpu_context": expected[left:right].hex(),
                    "gpu_context": actual[left:right].hex(),
                }
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ptx", type=Path, required=True)
    parser.add_argument("--cpu", type=Path, required=True)
    parser.add_argument("--kernel", help="override game_replay or game_bench")
    parser.add_argument("--device", type=int, default=0)
    parser.add_argument("--jobs", type=int)
    parser.add_argument("--ticks", type=int)
    parser.add_argument("--stride", type=int)
    parser.add_argument("--max-bytes", type=int, default=1024 * 1024 * 1024)
    parser.add_argument("--timeout", type=float, default=300)
    parser.add_argument(
        "--benchmark", action="store_true",
        help="compare final hashes with game_bench; excludes one CUDA warmup launch",
    )
    args = parser.parse_args()
    args.jobs = args.jobs if args.jobs is not None else (288 if args.benchmark else 2)
    args.ticks = args.ticks if args.ticks is not None else (720 if args.benchmark else 24)
    args.stride = args.stride if args.stride is not None else (0 if args.benchmark else 262144)

    if args.benchmark:
        if args.jobs <= 0 or args.ticks <= 0:
            raise ValueError("jobs and ticks must be positive")
        records, output_bytes, lengths_bytes = args.jobs, args.jobs * 8, 0
    else:
        records, output_bytes, lengths_bytes = checked_sizes(
            args.jobs, args.ticks, args.stride, args.max_bytes
        )
    with tempfile.TemporaryDirectory(prefix="melee-gpu-probe-") as directory:
        reference_path = Path(directory) / "reference.bin"
        cpu_wall_seconds, cpu_compute_seconds = run_cpu(
            args.cpu.resolve(), args.jobs, args.ticks,
            0 if args.benchmark else args.stride,
            reference_path, args.timeout, args.benchmark,
        )
        if args.benchmark:
            cpu_data = reference_path.read_bytes()
            if len(cpu_data) != output_bytes:
                raise ValueError(
                    f"CPU benchmark wrote {len(cpu_data)} bytes; expected {output_bytes}"
                )
            cpu_lengths = None
            reference_layout = "final-u64-hashes"
        else:
            cpu_data, cpu_lengths, reference_layout = load_reference(
                reference_path, records, output_bytes, args.stride
            )

        cuda = Cuda(args.device)
        cuda.call("cuCtxSetLimit", CU_LIMIT_MALLOC_HEAP_SIZE, 256 * 1024 * 1024)
        cuda.call("cuCtxSetLimit", CU_LIMIT_STACK_SIZE, 64 * 1024)
        kernel_name = args.kernel or ("game_bench" if args.benchmark else "game_replay")
        ptx_image, module, function = cuda.load_kernel(args.ptx.resolve(), kernel_name)
        # Keep PTX and module objects alive until the launch has completed.
        _ = ptx_image, module
        if args.benchmark:
            gpu_data, kernel_seconds, copy_seconds = run_gpu_benchmark(
                cuda, function, args.jobs, args.ticks
            )
            difference = None if cpu_data == gpu_data else {
                "kind": "final_hash",
                "job": next(
                    job for job in range(args.jobs)
                    if cpu_data[job * 8:(job + 1) * 8] != gpu_data[job * 8:(job + 1) * 8]
                ),
            }
            if difference:
                job = difference["job"]
                difference["cpu"] = cpu_data[job * 8:(job + 1) * 8].hex()
                difference["gpu"] = gpu_data[job * 8:(job + 1) * 8].hex()
        else:
            gpu_data, gpu_lengths, kernel_seconds, copy_seconds = run_gpu(
                cuda, function, args.jobs, args.ticks, args.stride,
                output_bytes, lengths_bytes,
            )
            difference = compare(
                cpu_data, cpu_lengths, gpu_data, gpu_lengths,
                args.jobs, args.ticks, args.stride,
            )

    report = {
        "match": difference is None,
        "mode": "benchmark" if args.benchmark else "trace",
        "kernel": kernel_name,
        "difference": difference,
        "jobs": args.jobs,
        "ticks": args.ticks,
        "stride": 0 if args.benchmark else args.stride,
        "records": records,
        "output_bytes": output_bytes,
        "reference_layout": reference_layout,
        "timing_seconds": {
            "cpu_wall": cpu_wall_seconds,
            "cpu_compute": cpu_compute_seconds,
            "gpu_kernel": kernel_seconds,
            "gpu_copy": copy_seconds,
        },
    }
    if kernel_seconds > 0:
        baseline = cpu_compute_seconds or cpu_wall_seconds
        report["kernel_speedup_vs_one_cpu_core"] = baseline / kernel_seconds
    print(json.dumps(report, sort_keys=True))
    return 0 if difference is None else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as exc:
        print(json.dumps({"error": str(exc)}))
        raise SystemExit(2)
