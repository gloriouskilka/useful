import torch
try:
    from _loader import load_and_pick_device  # запуск как модуль
except ImportError:
    import sys as _sys, pathlib as _pathlib
    _sys.path.append(str(_pathlib.Path(__file__).resolve().parent))
    from _loader import load_and_pick_device  # запуск как скрипт

device = load_and_pick_device()

# Фокус: использование реализации
x = torch.empty((2, 2), device=device)
x.fill_(1.0)
y = torch.add(x, x, alpha=1.0)

print('ready:', {'device': device, 'x': str(x.device), 'y': str(y.device), 'shape': tuple(y.shape)})
