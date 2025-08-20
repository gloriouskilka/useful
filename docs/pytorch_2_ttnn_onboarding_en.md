# PyTorch 2.0 TTNN: Integration with Tenstorrent

## Introduction to TTNN and Tenstorrent Integration

**PyTorch 2.0 TT-NN Compiler (TTNN)** is an extension of PyTorch that enables models to run on Tenstorrent AI accelerators. It preserves the familiar PyTorch API while offloading computations to Tenstorrent hardware for acceleration.

Essentially, TTNN introduces a new device type (Tenstorrent) and a backend compiler so PyTorch operations can execute on this device in two modes:

- **Eager mode** — operations are executed immediately, one by one.
- **Compiled mode** — the model is compiled as a whole and executed as an optimized graph.

For a PyTorch developer, this looks like just another device (besides CPU and CUDA): you simply move tensors or the model to the `"tt"` device.

**Tenstorrent hardware and TTNN library:**\
Tenstorrent accelerators (e.g., Grayskull, Wormhole) consist of a grid of Tensix cores (small RISC-V CPUs + tensor units), connected by a network-on-chip. They do not have caches or unified memory — only local SRAM, and data is explicitly moved via DMA.

Software stack:

- **TT-Metal** — low-level API (similar to ROCm/OpenCL), full control over memory and cores.
- **TTNN** — high-level library built on TT-Metal, with an interface similar to NumPy/PyTorch. TTNN manages tiled tensor layouts (e.g., 32×32 tiles), as well as Tenstorrent datatypes like BFloat8/BFloat16.

In short: **TTNN is the bridge between PyTorch and Tenstorrent hardware**.

---

## Eager Mode in TTNN

**Eager mode** = operations are executed immediately, one by one, directly on Tenstorrent hardware.

Example:

```python
import torch
import torch_ttnn
model = YourModel()

device = ttnn.open_device(0)
tt_device = torch_ttnn.ttnn_device_as_torch_device(device)

model.to(tt_device)              # move parameters to TT device
output = model(input_data)       # forward pass runs on Tenstorrent
```

PyTorch dispatcher detects that tensors are on the TT device and routes the operation to the **TTNN kernel**.

Under the hood:

1. **Input handling**: check format, tile, move to device.
2. **Call TTNN API**: e.g., `ttnn::add()` in C++.
3. **Execute on device**: via TT-Metal on Tenstorrent hardware.
4. **Return result**: a new `torch.Tensor` on TT device.

Diagram:

```mermaid
flowchart LR
    UserE[PyTorch code<br/>(e.g., x+z)] --> DispatcherE[PyTorch Dispatcher]
    DispatcherE --> KernelE[TTNN kernel (C++)]
    KernelE --> TTNNLibE[TTNN Library (C++)]
    TTNNLibE --> MetalE[TT-Metal Driver]
    MetalE --> HW[Tenstorrent Hardware]
```

**Notes:**

- Data inside TTNN is stored in **tiled format**.
- For debugging: `ttnn.from_torch` and `ttnn.to_torch` convert between formats.
- **Autograd:** gradients are either implemented in TTNN or fall back to CPU.
- **Fallback:** if an op isn’t implemented, TTNN uses the CPU op (with transfers).

**Debugging without hardware:**\
Fallback mode allows running everything on CPU through TTNN interfaces. This lets you verify integration correctness without a Tenstorrent card. Tests can compare TTNN outputs against pure PyTorch.

---

## Compiled Mode (Graph Execution)

**Compiled mode** is used via `torch.compile`, optimizing the graph as a whole:

```python
import torch
import torch_ttnn

device = ttnn.open_mesh_device(ttnn.MeshShape(1,2))
options = torch_ttnn.TorchTtnnOption(device=device, data_parallel=2)

model = torch.compile(model, backend=torch_ttnn.backend, options=options)
out = model(input_data)
```

Process:

1. **TorchDynamo** captures FX graph.
2. **TTNN backend** lowers it into TTNN operations.
3. **TTNN Graph Executor** compiles and runs it on the device.

```mermaid
flowchart LR
    UserGraph[torch.compile(model)] --> Dynamo[TorchDynamo (FX graph)]
    Dynamo --> Backend[TTNN backend]
    Backend --> TTNNExec[TTNN Graph Executor]
    TTNNExec --> Metal[TT-Metal Driver]
    Metal --> HWGraph[Tenstorrent Hardware]
```

**Advantages of compiled mode:**

- Optimizations: op fusion, minimized DRAM usage.
- Multi-device (mesh) support.
- Large performance boosts (up to tens of times faster).

---

## Project Structure

- `` — main Python package and C++ extension (device registration, ops).
- `` — graph tracing utilities.
- `` — documentation, design reports.
- `` — unit and end-to-end tests.
- `` — usage examples.

C++ part:

- Device registration via PyTorch `PrivateUse1` backend.
- Custom allocator + `DeviceGuard`.
- Op registration via `TORCH_LIBRARY_IMPL(aten, PrivateUse1, m)`.
- Optional backward implementations via `AutogradPrivateUse1`.

---

## How to Add Functionality in Eager Mode

1. **Implement the operation in TTNN (C++).**

   - Simple ops (e.g., ReLU) can be composites of existing ops.
   - Complex ops require a TT-Metal kernel.
   - Register in TTNN via `ttnn::register_operation`.

2. **Register a kernel in PyTorch.**

   ```cpp
   TORCH_LIBRARY_IMPL(aten, PrivateUse1, m) {
       m.impl("silu", TORCH_FN(ttnn_silu_forward));
   }
   ```

   Here, `ttnn_silu_forward` calls `ttnn::silu`.

3. **Fallback and golden function.**\
   For testing: `ttnn.attach_golden_function` provides a CPU reference.

4. **Backward (optional).**

   - Either let autograd handle it (composition).
   - Or implement/register a custom backward kernel.

5. **Testing.**

   - Compare TTNN and CPU results.
   - Check broadcasting, multiple dtypes (often BF16).

6. **Integration with compiled mode.**

   - Ensure compiler lowering can map FX ops to your kernel.
   - Sometimes add lowering rules in `tracer/`.

---

## Conclusion

**The big picture:**

- **Eager mode** — convenient for debugging, step-by-step execution, CPU fallback.
- **Compiled mode** — optimized for performance, executes whole graphs.
- TTNN = Python + C++ extensions + PyTorch dispatcher + TT-Metal library.

**Developer tasks:**

- Implement missing operations.
- Ensure correctness with golden functions and fallbacks.
- Mind tiling layouts and memory constraints.

**Resources:**

- [TTNN GitHub README and examples](https://github.com/tenstorrent/pytorch2.0_ttnn)
- [PyTorch docs on PrivateUse1](https://pytorch.org/tutorials/advanced/extend_dispatcher.html)
- [Martin’s blog on Tenstorrent HW](https://martinsos.dev/blog/tenstorrent-architecture)
- [TTNN docs: contributing guide](https://docs.tenstorrent.com)

