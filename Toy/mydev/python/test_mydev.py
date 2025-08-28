import torch
try:
    from _loader import load_and_pick_device
except ImportError:
    import sys as _sys, pathlib as _pathlib
    _sys.path.append(str(_pathlib.Path(__file__).resolve().parent))
    from _loader import load_and_pick_device

device = load_and_pick_device()

print('Device picked:', device)

# 1) empty + fill_ + add
x = torch.empty((5, 3), device=device)
x.fill_(1.0)

y = torch.empty_like(x)
y.fill_(2.0)

z = torch.add(x, y, alpha=1.0)
zc = torch.empty_like(z, device='cpu')
torch.ops.aten._copy_from(z, zc, False)
assert torch.allclose(zc, torch.full_like(zc, 3.0))
print('OK: add / fill_')

# 2) zeros / ones
z0 = torch.zeros((2, 4), device=device)
z1 = torch.ones((2, 4), device=device)
z0c = torch.empty_like(z0, device='cpu')
z1c = torch.empty_like(z1, device='cpu')
torch.ops.aten._copy_from(z0, z0c, False)
torch.ops.aten._copy_from(z1, z1c, False)
assert torch.allclose(z0c, torch.zeros_like(z0c))
assert torch.allclose(z1c, torch.ones_like(z1c))
print('OK: zeros / ones')

# 3) mul.Tensor
a = torch.ones((3, 3), device=device)
b = torch.ones((3, 3), device=device)
b = b.add(b)  # теперь все двойки на mydev
m = torch.mul(a, b)
mc = torch.empty_like(m, device='cpu')
torch.ops.aten._copy_from(m, mc, False)
assert torch.allclose(mc, torch.full_like(mc, 2.0))
print('OK: mul.Tensor')

# 4) relu / relu_
neg = torch.empty((2, 2), device=device)
neg.fill_(-1.0)
pos = torch.empty((2, 2), device=device)
pos.fill_(2.0)
mix = torch.add(neg, pos)  # значения 1.0
r = torch.relu(torch.add(neg, pos))
rc = torch.empty_like(r, device='cpu')
torch.ops.aten._copy_from(r, rc, False)
assert torch.allclose(rc, torch.full_like(rc, 1.0))

mix.relu_()
mixc = torch.empty_like(mix, device='cpu')
torch.ops.aten._copy_from(mix, mixc, False)
assert torch.all(mixc >= 0)
print('OK: relu / relu_')

# 5) copy_ и _copy_from: CPU <-> mydev
cpu = torch.full((2, 2), 3.0)
dev = torch.empty((2, 2), device=device)
dev.copy_(cpu)  # CPU -> mydev
assert torch.allclose(dev.to('cpu'), cpu)

cpu2 = torch.empty_like(cpu)
torch.ops.aten._copy_from(dev, cpu2, False)  # mydev -> CPU
assert torch.allclose(cpu2, cpu)
print('OK: copy_ and _copy_from')


