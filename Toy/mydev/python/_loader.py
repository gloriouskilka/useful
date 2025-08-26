import pathlib
import sys
import types
import torch

ROOT = pathlib.Path(__file__).resolve().parents[1]
TOP = ROOT.parent

def find_library() -> pathlib.Path:
    candidates = [
        TOP / 'build-py' / 'py-debug' / 'mydev_backend.so',
        TOP / 'build-py' / 'py-release' / 'mydev_backend.so',
        TOP / 'build-vcpkg' / 'linux-debug' / 'mydev_backend.so',
        TOP / 'build' / 'mydev_backend.so',
        ROOT / 'build-py' / 'py-debug' / 'mydev_backend.so',
        ROOT / 'build-py' / 'py-release' / 'mydev_backend.so',
        ROOT / 'build-vcpkg' / 'linux-debug' / 'mydev_backend.so',
        ROOT / 'build-vcpkg' / 'linux-release' / 'mydev_backend.so',
        ROOT / 'build' / 'mydev_backend.so',
    ]
    for p in candidates:
        if p.exists():
            return p
    raise FileNotFoundError("Не найден mydev_backend.so — соберите проект (Build (py-debug))")

def load_and_pick_device() -> str:
    lib = find_library()
    torch.ops.load_library(str(lib))
    if 'torch.mydev' not in sys.modules:
        sys.modules['torch.mydev'] = types.ModuleType('torch.mydev')
    if hasattr(torch.utils, 'generate_methods_for_privateuse1_backend'):
        torch.utils.generate_methods_for_privateuse1_backend(for_tensor=True, for_storage=True)

    for dev in ('mydev:0', 'privateuseone:0'):
        try:
            torch.empty((1,), device=dev)
            return dev
        except Exception:
            continue
    raise RuntimeError("Не удалось создать тензор на PrivateUse1 (ни 'mydev:0', ни 'privateuseone:0')")


