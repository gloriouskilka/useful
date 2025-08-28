import torch
try:
    from _loader import load_and_pick_device  # запуск как модуль
except ImportError:
    import sys as _sys, pathlib as _pathlib
    _sys.path.append(str(_pathlib.Path(__file__).resolve().parent))
    from _loader import load_and_pick_device  # запуск как скрипт

device = load_and_pick_device()

# Демонстрация доступных операций
print('device:', device)

x = torch.ones((2, 2), device=device)
y = torch.zeros((2, 2), device=device)
z = torch.add(x, x)
m = torch.mul(z, z)  # (2+2)^2 = 16 для каждого элемента
r = torch.relu(z.add(torch.tensor(-1.0, device=device)))

print('ops:', {
    'x': str(x.device),
    'y': str(y.device),
    'z': tuple(z.shape),
    'm[0,0]': float(m.to('cpu')[0,0]),
    'r_min': float(r.to('cpu').min()),
})
