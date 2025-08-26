import torch
try:
    from _loader import load_and_pick_device
except ImportError:
    import sys as _sys, pathlib as _pathlib
    _sys.path.append(str(_pathlib.Path(__file__).resolve().parent))
    from _loader import load_and_pick_device

device = load_and_pick_device()

x = torch.empty((5, 3), device=device)
x.fill_(1.0)

y = torch.empty_like(x)
y.fill_(2.0)

z = torch.add(x, y, alpha=1.0)

print('x.device =', x.device)
print('y.device =', y.device)
print('z.device =', z.device)

# Проверка значений: переводим через .to('cpu') только для чтения результата
zc = z.to('cpu')
print('zc shape =', zc.shape, 'value[0,0]=', float(zc[0,0]))
assert torch.allclose(zc, torch.full_like(zc, 3.0))
print('OK: mydev add + empty работают, fill_ реализован')


