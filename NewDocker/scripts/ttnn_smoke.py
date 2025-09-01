import os
import sys


def main() -> int:
    print("== TTNN smoke test ==")
    print("PYTHONPATH:", os.environ.get("PYTHONPATH", ""))
    print("TT_METAL_HOME:", os.environ.get("TT_METAL_HOME", "(unset)"))

    try:
        import torch  # noqa: F401
    except Exception as e:
        print("torch import FAILED:", repr(e))
        return 2

    import torch
    print("torch version:", torch.__version__)
    print("torch file:", torch.__file__)
    try:
        print("torch cmake_prefix:", torch.utils.cmake_prefix_path)
    except Exception:
        pass

    try:
        import torch_ttnn as ttnn  # noqa: F401
    except Exception as e:
        print("torch_ttnn import FAILED:", repr(e))
        return 3

    import torch_ttnn as ttnn
    print("torch_ttnn version:", getattr(ttnn, "__version__", "n/a"))
    print("torch_ttnn file:", getattr(ttnn, "__file__", "n/a"))

    # Optional: probe submodules commonly exposed by the package
    try:
        from torch_ttnn import backend  # noqa: F401
        print("backend module: OK")
    except Exception as e:
        print("backend module import FAILED:", repr(e))

    print("OK: imports look fine")
    return 0


if __name__ == "__main__":
    sys.exit(main())


