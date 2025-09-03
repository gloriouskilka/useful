import os
import sys
import importlib
import site
from pathlib import Path

def print_header(title: str) -> None:
    print("\n== {} ==".format(title))

def try_import(name: str):
    try:
        mod = importlib.import_module(name)
        print(f"[ok] import {name}: {getattr(mod, '__file__', None)}")
        return mod
    except Exception as e:
        print(f"[fail] import {name}: {e!r}")
        return None

def main() -> None:
    print_header("Env")
    print("python:", sys.executable)
    print("version:", sys.version)
    print("VIRTUAL_ENV:", os.environ.get("VIRTUAL_ENV", ""))
    print("PYTHONPATH:", os.environ.get("PYTHONPATH", ""))
    print("TT_METAL_HOME:", os.environ.get("TT_METAL_HOME", ""))
    print("Torch_DIR:", os.environ.get("Torch_DIR", ""))

    print_header("sys.path (top 50)")
    for p in sys.path[:50]:
        print(" ", p)

    print_header("site-packages")
    for sp in site.getsitepackages() + [site.getusersitepackages()]:
        print(" ", sp)

    print_header("pip discover torch/ttnn")
    try:
        import pkgutil
        names = [m.name for m in pkgutil.iter_modules() if m.name in ("torch", "torch_ttnn", "ttnn")]
        print("found:", names)
    except Exception as e:
        print("[warn] pkgutil failed:", e)

    print_header("imports")
    torch = try_import("torch")
    if torch is not None:
        print("torch.__version__:", getattr(torch, "__version__", None))
        print("torch.__file__:", getattr(torch, "__file__", None))

    # torch_ttnn top-level package
    ttnn_pkg = try_import("torch_ttnn")
    # compiled cpp extension within torch_ttnn (if any)
    try_import("torch_ttnn_cpp_extension")

    # standalone ttnn package (pypi) if present
    try_import("ttnn")

    print_header("candidate editable installs in workspace")
    ws = Path("/workspace")
    candidates = [
        ws / "pytorch2.0_ttnn",
        ws / "pytorch2.0_ttnn" / "torch_ttnn",
        ws / "pytorch2.0_ttnn" / "torch_ttnn" / "cpp_extension",
    ]
    for c in candidates:
        print(" ", c, "exists=", c.exists())

    print_header("egg-info / dist-info hints")
    for base in [Path(sp) for sp in site.getsitepackages() + [site.getusersitepackages()]]:
        if not base.exists():
            continue
        for p in base.glob("*torch_ttnn*info"):
            print(" ", p)
        for p in base.glob("*torch_ttnn_cpp_extension*info"):
            print(" ", p)

    print_header("done")

if __name__ == "__main__":
    main()


