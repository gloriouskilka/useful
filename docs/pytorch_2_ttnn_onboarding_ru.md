# PyTorch 2.0 TTNN: Интеграция с Tenstorrent

## Введение в TTNN и интеграцию с Tenstorrent

**PyTorch 2.0 TT-NN Compiler (TTNN)** — это расширение PyTorch, позволяющее выполнять модели на AI-ускорителях Tenstorrent . Оно сохраняет привычный API PyTorch, но вычисления переносятся на аппарат Tenstorrent для ускорения .

По сути, TTNN добавляет новый тип устройства (Tenstorrent) и бэкенд-компилятор, так что операции PyTorch можно выполнять на этом устройстве в двух режимах:

- **eager (нетерпеливый) режим** — операции исполняются сразу, по одной;
- **compiled (графовый) режим** — модель компилируется целиком, и граф исполняется оптимизированным кодом  .

Для разработчика PyTorch это выглядит как ещё одно устройство наряду с CPU и CUDA: нужно просто перенести тензоры или модель на устройство `"tt"`.

**Аппарат Tenstorrent и библиотека TTNN:**\
Аппаратура Tenstorrent (например, Grayskull, Wormhole) состоит из сетки ядер Tensix (малые процессоры RISC-V + тензорные блоки), соединённых через сетевую топологию  . У них нет кэша или общей памяти — только локальная SRAM, и данные перемещаются явным образом через DMA  .

Софт Tenstorrent:

- **TT-Metal** — низкоуровневый API (аналог ROCm/OpenCL), полный контроль над памятью и ядрами .
- **TTNN** — библиотека высокого уровня, построенная на TT-Metal, с интерфейсом, похожим на NumPy/PyTorch . TTNN управляет тайлинговыми форматами тензоров (например, 32×32 тайлы)  , а также типами данных BFloat8/BFloat16.

Итого: **TTNN — это мост между PyTorch и “железом” Tenstorrent**.

---

## Eager-режим в TTNN

**Eager mode** = операции выполняются немедленно, одна за другой, прямо на устройстве Tenstorrent.

Пример использования:

```python
import torch
import torch_ttnn
model = YourModel()

device = ttnn.open_device(0)  
tt_device = torch_ttnn.ttnn_device_as_torch_device(device)

model.to(tt_device)              # перенесли параметры на устройство TT
output = model(input_data)       # вперёд-проход выполняется на Tenstorrent
```

PyTorch-диспетчер определяет, что тензоры находятся на устройстве TT, и направляет операцию в **TTNN kernel**  .

Под капотом:

1. **Обработка входа**: проверка формата, тайлинг, перенос на устройство.
2. **Вызов TTNN API**: например, `ttnn::add()` в C++.
3. **Запуск на устройстве**: через TT-Metal на аппарат Tenstorrent.
4. **Возврат результата**: новый `torch.Tensor` с типом устройства TT.

Диаграмма:

```mermaid
flowchart LR
    UserE[PyTorch код<br/>(например, x+z)] --> DispatcherE[Dispatcher PyTorch]
    DispatcherE --> KernelE[TTNN kernel (C++)]
    KernelE --> TTNNLibE[Библиотека TTNN (C++)]
    TTNNLibE --> MetalE[TT-Metal Driver]
    MetalE --> HW[Аппарат Tenstorrent]
```

**Особенности:**

- Данные внутри TTNN хранятся в **тайлинговом формате** .
- Для отладки: `ttnn.from_torch` и `ttnn.to_torch` позволяют конвертировать туда-обратно  .
- **Autograd:** градиенты либо реализованы в TTNN, либо PyTorch делает backward на CPU.
- **Fallback:** если операция не реализована, TTNN вызывает CPU-версию, копируя туда-сюда .

**Отладка без железа:**\
Можно использовать fallback-режим, т.е. все операции будут выполняться на CPU, но через интерфейсы TTNN. Это позволяет проверить корректность интеграции без карты. В тестах можно сравнивать вывод TTNN и чистого PyTorch.

---

## Compiled-режим (графовый)

**Compiled mode** используется через `torch.compile`, оптимизация графа целиком :

```python
import torch
import torch_ttnn

device = ttnn.open_mesh_device(ttnn.MeshShape(1,2))
options = torch_ttnn.TorchTtnnOption(device=device, data_parallel=2)

model = torch.compile(model, backend=torch_ttnn.backend, options=options)
out = model(input_data)
```

Процесс:

1. **TorchDynamo** снимает FX-граф.
2. **TTNN backend** преобразует его в последовательность TTNN операций.
3. **TTNN Graph Executor** компилирует и запускает на устройстве.

```mermaid
flowchart LR
    UserGraph[torch.compile(model)] --> Dynamo[TorchDynamo (FX graph)]
    Dynamo --> Backend[TTNN backend]
    Backend --> TTNNExec[TTNN Graph Executor]
    TTNNExec --> Metal[TT-Metal Driver]
    Metal --> HWGraph[Аппарат Tenstorrent]
```

**Плюсы compiled-режима:**

- Оптимизации: фьюзинг операций, минимизация обращений к DRAM .
- Использование мульти-девайс (mesh) .
- Значительные ускорения — вплоть до десятков раз .

---

## Структура проекта

- \`\` — основная Python-библиотека и C++ расширение (регистрация устройства, операций).
- \`\` — инструменты для работы с графами.
- \`\` — документация, отчёты о дизайне.
- \`\` — тесты (юнит и end-to-end) .
- \`\` — примеры использования.

C++ часть:

- Регистрация устройства через `PrivateUse1` backend PyTorch .
- Аллокатор памяти + `DeviceGuard`.
- Регистрация операций через `TORCH_LIBRARY_IMPL(aten, PrivateUse1, m)` .
- При необходимости — реализации backward через `AutogradPrivateUse1`.

---

## Как добавлять функциональность в eager-режиме

1. **Реализовать операцию в TTNN (C++).**

   - Если простая (например, ReLU) — композитная из других ops.
   - Если сложная — ядро через TT-Metal.
   - Зарегистрировать в TTNN через `ttnn::register_operation` .

2. **Зарегистрировать kernel в PyTorch.**

   ```cpp
   TORCH_LIBRARY_IMPL(aten, PrivateUse1, m) {
       m.impl("silu", TORCH_FN(ttnn_silu_forward));
   }
   ```

   Здесь `ttnn_silu_forward` вызывает `ttnn::silu`.

3. **Fallback и golden-функция.**\
   Для тестов: `ttnn.attach_golden_function` — эталон через CPU .

4. **Backward (опционально).**

   - Либо доверить autograd (через композицию).
   - Либо реализовать и зарегистрировать явный backward kernel.

5. **Тестирование.**

   - Сравнить результаты TTNN и CPU.
   - Проверить broadcast, разные dtype (чаще всего BF16).

6. **Интеграция с compiled-режимом.**

   - Если компилятор видит FX-операцию, он должен уметь её отобразить на ваш kernel.
   - Иногда нужно дописать правила lowering в `tracer/`.

---

## Заключение

**Общая картина:**

- **Eager mode** — удобно для отладки, пошаговое выполнение, fallback на CPU.
- **Compiled mode** — для производительности, оптимизация графа целиком.
- TTNN = связка Python+C++ расширений, диспетчер PyTorch + библиотека TT-Metal.

**Задачи разработчика:**

- Реализовать недостающие операции.
- Обеспечить корректность через golden-функции и fallback.
- Учитывать особенности тайлинга и ограничений памяти.

**Ресурсы:**

- [TTNN GitHub README и примеры](https://github.com/tenstorrent/pytorch2.0_ttnn)
- [Документация PyTorch о PrivateUse1](https://pytorch.org/tutorials/advanced/extend_dispatcher.html)
- [Блог Martin о Tenstorrent HW](https://martinsos.dev/blog/tenstorrent-architecture)
- [TTNN docs: contributing guide](https://docs.tenstorrent.com)

