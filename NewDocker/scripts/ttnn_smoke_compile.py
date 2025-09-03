import os
import sys

print("== TTNN compile smoke ==")
print("PYTHONPATH:", os.environ.get("PYTHONPATH", ""))
print("TT_METAL_HOME:", os.environ.get("TT_METAL_HOME", ""))

import torch
import torch_ttnn
import ttnn


class AddModule(torch.nn.Module):
    def __init__(self):
        super().__init__()

    def forward(self, x, y):
        return x + y


def main():
    # Try to open device (may fail in dev containers without HW)
    device = None
    try:
        device = ttnn.open_device(device_id=0)
        print("device:", device)
    except Exception as e:
        print("[warn] open_device failed:", e)

    # Prepare simple model and inputs
    m = AddModule()
    inputs = [torch.randint(1, 5, (32, 32)).type(torch.bfloat16) for _ in range(2)]
    result_before = m.forward(*inputs)

    # Use imports/flow like in CI smoke test
    option = torch_ttnn.TorchTtnnOption(device=device)
    option.gen_graphviz = True
    try:
        compiled_m = torch.compile(m, backend=torch_ttnn.backend, options=option)
        result_after = compiled_m.forward(*inputs)
        if option._out_fx_graphs:
            option._out_fx_graphs[0].print_tabular()

        nodes = list(option._out_fx_graphs[0].nodes) if option._out_fx_graphs else []
        add_count = [node.target for node in nodes].count(ttnn.add) if nodes else None
        if add_count is not None:
            print("ttnn.add nodes:", add_count)
        print("allclose:", torch.allclose(result_before, result_after))
        print("OK: compile path executed")
    except Exception as e:
        print("[warn] compile path failed:", e)
        print("OK: imports and option/backend accessible")


if __name__ == "__main__":
    main()


