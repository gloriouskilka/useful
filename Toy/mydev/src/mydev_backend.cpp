#include <ATen/ATen.h>
#include <ATen/Tensor.h>
#include <ATen/Context.h>
#include <cstring>
#include <ATen/native/CPUFallback.h>
#include <c10/core/Allocator.h>
#include <c10/core/Device.h>
#include <c10/core/DeviceGuard.h>
#include <c10/core/DeviceType.h>
#include <c10/core/DispatchKeySet.h>
#include <c10/core/ScalarType.h>
#include <c10/core/TensorImpl.h>
#include <torch/library.h>
#include <algorithm>

namespace {

// === 1) Device rename ===
struct MyDevBackendNameRegisterer {
    MyDevBackendNameRegisterer() {
        c10::register_privateuse1_backend("mydev");
    }
};
static MyDevBackendNameRegisterer _mydev_name_reg_;

// === 2) Минимальный DeviceGuard ===
struct MyDevGuardImpl final : public c10::impl::DeviceGuardImplInterface {
    c10::DeviceType type() const override { return c10::DeviceType::PrivateUse1; }

    c10::Device exchangeDevice(c10::Device d) const override {
        int old = current_device_;
        current_device_ = d.index();
        return c10::Device(c10::DeviceType::PrivateUse1, old);
    }
    c10::Device getDevice() const override {
        return c10::Device(c10::DeviceType::PrivateUse1, current_device_);
    }
    void setDevice(c10::Device d) const override { current_device_ = d.index(); }
    void uncheckedSetDevice(c10::Device d) const noexcept override { current_device_ = d.index(); }

    c10::Stream getStream(c10::Device d) const noexcept override {
        return c10::Stream(c10::Stream::Default{}, d);
    }
    c10::Stream exchangeStream(c10::Stream s) const noexcept override {
        return s;
    }
    c10::DeviceIndex deviceCount() const noexcept override { return 1; }
private:
    static thread_local int current_device_;
};
thread_local int MyDevGuardImpl::current_device_ = 0;
C10_REGISTER_GUARD_IMPL(PrivateUse1, MyDevGuardImpl);

// === 3) Создать TensorImpl со Storage на CPU, но с ключом PrivateUse1 ===
static at::Tensor mydev_empty_impl(
    c10::IntArrayRef sizes,
    c10::ScalarType dtype,
    c10::optional<c10::MemoryFormat> memory_format
) {
    size_t nbytes = at::elementSize(dtype);
    for (auto s : sizes) nbytes *= static_cast<size_t>(s);

    at::Allocator* cpu_alloc = at::getCPUAllocator();
    void* raw_ptr = cpu_alloc->raw_allocate(nbytes);
    c10::DeleterFnPtr deleter = cpu_alloc->raw_deleter();

    // Маскируем CPU-буфер как PrivateUse1, чтобы тензор имел нужное устройство
    c10::DataPtr dptr(raw_ptr, raw_ptr, deleter, c10::Device(c10::DeviceType::PrivateUse1, 0));

    c10::Storage storage(
        c10::Storage::use_byte_size_t(),
        nbytes,
        std::move(dptr),
        cpu_alloc,
        /*resizable=*/true
    );

    c10::DispatchKeySet dkeys;
    dkeys = dkeys.add(c10::DispatchKey::PrivateUse1);
    dkeys = dkeys.add(c10::DispatchKey::AutogradPrivateUse1);

    auto t_impl = c10::make_intrusive<at::TensorImpl>(
        std::move(storage),
        dkeys,
        caffe2::TypeMeta::fromScalarType(dtype)
    );

    t_impl->set_sizes_contiguous(sizes);

    at::Tensor t(std::move(t_impl));
    (void)memory_format;
    return t;
}

// === 4) Реализация aten::empty.memory_format под PrivateUse1 ===
static at::Tensor mydev_empty(
    c10::IntArrayRef size,
    c10::optional<c10::ScalarType> dtype_opt,
    c10::optional<c10::Layout> layout_opt,
    c10::optional<c10::Device> device_opt,
    c10::optional<bool> pin_memory_opt,
    c10::optional<c10::MemoryFormat> memory_format_opt
) {
    TORCH_CHECK(!layout_opt.has_value() || layout_opt.value() == c10::Layout::Strided,
                "mydev: поддерживается только Layout::Strided");

    c10::ScalarType dtype = dtype_opt.value_or(c10::ScalarType::Float);
    (void)device_opt;
    (void)pin_memory_opt;

    return mydev_empty_impl(size, dtype, memory_format_opt);
}

// === 5b) Реализация aten::empty_strided под PrivateUse1 ===
static at::Tensor mydev_empty_strided(
    c10::IntArrayRef size,
    c10::IntArrayRef stride,
    c10::optional<c10::ScalarType> dtype_opt,
    c10::optional<c10::Layout> layout_opt,
    c10::optional<c10::Device> device_opt,
    c10::optional<bool> pin_memory_opt
) {
    TORCH_CHECK(!layout_opt.has_value() || layout_opt.value() == c10::Layout::Strided,
                "mydev: поддерживается только Layout::Strided");

    c10::ScalarType dtype = dtype_opt.value_or(c10::ScalarType::Float);
    (void)device_opt;
    (void)pin_memory_opt;

    // вычисляем требуемый размер буфера в элементах:
    // total_elems = (sum_i ( (size[i]-1) * stride[i] )) + 1, при size>0, иначе 0
    size_t numel_bytes = 0;
    if (!size.empty()) {
        bool any_zero = false;
        int64_t max_offset = 0;
        for (int64_t i = 0; i < static_cast<int64_t>(size.size()); ++i) {
            if (size[i] == 0) { any_zero = true; break; }
            max_offset += (size[i] - 1) * stride[i];
        }
        int64_t total_elems = any_zero ? 0 : (max_offset + 1);
        numel_bytes = static_cast<size_t>(std::max<int64_t>(total_elems, 0)) * at::elementSize(dtype);
    }

    at::Allocator* cpu_alloc = at::getCPUAllocator();
    void* raw_ptr = numel_bytes ? cpu_alloc->raw_allocate(numel_bytes) : nullptr;
    c10::DeleterFnPtr deleter = cpu_alloc->raw_deleter();

    c10::DataPtr dptr(raw_ptr, raw_ptr, deleter, c10::Device(c10::DeviceType::PrivateUse1, 0));

    c10::Storage storage(
        c10::Storage::use_byte_size_t(),
        numel_bytes,
        std::move(dptr),
        cpu_alloc,
        /*resizable=*/true
    );

    c10::DispatchKeySet dkeys;
    dkeys = dkeys.add(c10::DispatchKey::PrivateUse1);
    dkeys = dkeys.add(c10::DispatchKey::AutogradPrivateUse1);

    auto t_impl = c10::make_intrusive<at::TensorImpl>(
        std::move(storage),
        dkeys,
        caffe2::TypeMeta::fromScalarType(dtype)
    );
    t_impl->set_sizes_and_strides(size, stride);

    at::Tensor t(std::move(t_impl));
    return t;
}

// === 5) Реализация aten::add.Tensor под PrivateUse1 ===
static at::Tensor mydev_add(const at::Tensor& a, const at::Tensor& b, const at::Scalar& alpha) {
    TORCH_CHECK(a.device().type() == c10::DeviceType::PrivateUse1,
                "mydev_add: tensor 'a' не на устройстве mydev");
    TORCH_CHECK(a.scalar_type() == c10::ScalarType::Float,
                "mydev_add: поддерживается только float32");

    at::Tensor out = mydev_empty_impl(a.sizes(), a.scalar_type(), c10::nullopt);

    auto* ap = reinterpret_cast<float*>(a.data_ptr());
    const auto b_dev = b.device().type();
    TORCH_CHECK(b_dev == c10::DeviceType::PrivateUse1 || b_dev == c10::DeviceType::CPU,
                "mydev_add: tensor 'b' должен быть на устройстве mydev или CPU");
    auto* op = reinterpret_cast<float*>(out.data_ptr());

    float alpha_f = alpha.toFloat();
    size_t n = a.numel();

    // Поддержка скалярного b (0-мерный тензор): treat как Scalar с приведением к float
    if (b.numel() == 1) {
        float b_val = 0.0f;
        if (b.scalar_type() == c10::ScalarType::Float) {
            b_val = *reinterpret_cast<const float*>(b.data_ptr());
        } else if (b.scalar_type() == c10::ScalarType::Double) {
            b_val = static_cast<float>(*reinterpret_cast<const double*>(b.data_ptr()));
        } else {
            TORCH_CHECK(false, "mydev_add: скаляр b поддерживается только float/double");
        }
        for (size_t i = 0; i < n; ++i) {
            op[i] = ap[i] + alpha_f * b_val;
        }
        return out;
    }

    // Иначе требуем совпадения dtype и размеров (без broadcasting)
    TORCH_CHECK(b.scalar_type() == a.scalar_type(), "mydev_add: dtype должен совпадать");
    TORCH_CHECK(a.sizes() == b.sizes(), "mydev_add: требуем одинаковые размеры без broadcasting");
    auto* bp = reinterpret_cast<float*>(b.data_ptr());
    for (size_t i = 0; i < n; ++i) {
        op[i] = ap[i] + alpha_f * bp[i];
    }
    return out;
}

// === 5a) Реализация aten::add.Scalar под PrivateUse1 ===
static at::Tensor mydev_add_scalar(const at::Tensor& a, const at::Scalar& b, const at::Scalar& alpha) {
    TORCH_CHECK(a.device().type() == c10::DeviceType::PrivateUse1,
                "mydev_add_scalar: tensor 'a' не на устройстве mydev");
    TORCH_CHECK(a.scalar_type() == c10::ScalarType::Float,
                "mydev_add_scalar: поддерживается только float32");

    at::Tensor out = mydev_empty_impl(a.sizes(), a.scalar_type(), c10::nullopt);

    auto* ap = reinterpret_cast<float*>(a.data_ptr());
    auto* op = reinterpret_cast<float*>(out.data_ptr());
    float b_f = b.toFloat();
    float alpha_f = alpha.toFloat();
    size_t n = a.numel();
    for (size_t i = 0; i < n; ++i) {
        op[i] = ap[i] + alpha_f * b_f;
    }
    return out;
}

// === 5c) Реализация aten::_copy_from под PrivateUse1 (поддерживаем CPU<->mydev и mydev<->mydev) ===
static at::Tensor mydev__copy_from(const at::Tensor& self, const at::Tensor& dst, bool non_blocking) {
    (void)non_blocking;

    TORCH_CHECK(self.scalar_type() == dst.scalar_type(), "dtype mismatch in _copy_from");
    TORCH_CHECK(self.sizes() == dst.sizes(), "size mismatch in _copy_from");
    TORCH_CHECK(self.is_contiguous() && dst.is_contiguous(), "_copy_from: поддерживается только contiguous");

    const auto src_dev = self.device().type();
    const auto dst_dev = dst.device().type();

    // Поддерживаем направления: mydev->CPU, CPU->mydev, mydev->mydev
    bool src_supported = (src_dev == c10::DeviceType::PrivateUse1) || (src_dev == c10::DeviceType::CPU);
    bool dst_supported = (dst_dev == c10::DeviceType::PrivateUse1) || (dst_dev == c10::DeviceType::CPU);
    TORCH_CHECK(src_supported && dst_supported, "mydev__copy_from: поддерживаются только CPU и mydev");

    size_t nbytes = static_cast<size_t>(self.numel()) * at::elementSize(self.scalar_type());
    if (nbytes == 0) return dst;
    void* dst_ptr = dst.data_ptr();
    const void* src_ptr = self.data_ptr();
    TORCH_CHECK(dst_ptr != nullptr && src_ptr != nullptr, "_copy_from: null data_ptr with nonzero size");
    std::memcpy(dst_ptr, src_ptr, nbytes);
    return dst;
}

// === 5d) Реализация aten::mul.Tensor под PrivateUse1 ===
static at::Tensor mydev_mul(const at::Tensor& a, const at::Tensor& b) {
    TORCH_CHECK(a.device().type() == c10::DeviceType::PrivateUse1,
                "mydev_mul: tensor 'a' не на устройстве mydev");
    TORCH_CHECK(a.scalar_type() == c10::ScalarType::Float,
                "mydev_mul: поддерживается только float32");
    TORCH_CHECK(b.scalar_type() == a.scalar_type(),
                "mydev_mul: dtype должен совпадать");
    TORCH_CHECK(a.sizes() == b.sizes(),
                "mydev_mul: требуем одинаковые размеры без broadcasting");

    at::Tensor out = mydev_empty_impl(a.sizes(), a.scalar_type(), c10::nullopt);

    auto* ap = reinterpret_cast<float*>(a.data_ptr());
    const auto b_dev = b.device().type();
    TORCH_CHECK(b_dev == c10::DeviceType::PrivateUse1 || b_dev == c10::DeviceType::CPU,
                "mydev_mul: tensor 'b' должен быть на устройстве mydev или CPU");
    auto* bp = reinterpret_cast<float*>(b.data_ptr());
    auto* op = reinterpret_cast<float*>(out.data_ptr());

    size_t n = a.numel();
    for (size_t i = 0; i < n; ++i) {
        op[i] = ap[i] * bp[i];
    }
    return out;
}

// === 5e) Реализация aten::relu и aten::relu_ под PrivateUse1 ===
static at::Tensor mydev_relu(const at::Tensor& self) {
    TORCH_CHECK(self.device().type() == c10::DeviceType::PrivateUse1,
                "mydev_relu: tensor не на устройстве mydev");
    TORCH_CHECK(self.scalar_type() == c10::ScalarType::Float,
                "mydev_relu: поддерживается только float32");

    at::Tensor out = mydev_empty_impl(self.sizes(), self.scalar_type(), c10::nullopt);
    auto* sp = reinterpret_cast<float*>(self.data_ptr());
    auto* op = reinterpret_cast<float*>(out.data_ptr());
    size_t n = self.numel();
    for (size_t i = 0; i < n; ++i) {
        float v = sp[i];
        op[i] = v > 0.0f ? v : 0.0f;
    }
    return out;
}

static at::Tensor& mydev_relu_(at::Tensor& self) {
    TORCH_CHECK(self.device().type() == c10::DeviceType::PrivateUse1,
                "mydev_relu_: tensor не на устройстве mydev");
    TORCH_CHECK(self.scalar_type() == c10::ScalarType::Float,
                "mydev_relu_: поддерживается только float32");

    auto* sp = reinterpret_cast<float*>(self.data_ptr());
    size_t n = self.numel();
    for (size_t i = 0; i < n; ++i) {
        if (sp[i] < 0.0f) sp[i] = 0.0f;
    }
    return self;
}

// === 5f) Реализация aten::zeros.memory_format и aten::ones.memory_format под PrivateUse1 ===
static at::Tensor mydev_zeros(
    c10::IntArrayRef size,
    c10::optional<c10::ScalarType> dtype_opt,
    c10::optional<c10::Layout> layout_opt,
    c10::optional<c10::Device> device_opt,
    c10::optional<bool> pin_memory_opt
) {
    TORCH_CHECK(!layout_opt.has_value() || layout_opt.value() == c10::Layout::Strided,
                "mydev: поддерживается только Layout::Strided");
    c10::ScalarType dtype = dtype_opt.value_or(c10::ScalarType::Float);
    (void)device_opt; (void)pin_memory_opt;
    at::Tensor t = mydev_empty_impl(size, dtype, c10::nullopt);
    if (dtype == c10::ScalarType::Float) {
        auto* p = reinterpret_cast<float*>(t.data_ptr());
        size_t n = t.numel();
        for (size_t i = 0; i < n; ++i) p[i] = 0.0f;
        return t;
    }
    TORCH_CHECK(false, "mydev_zeros: поддерживается только float32");
}

static at::Tensor mydev_ones(
    c10::IntArrayRef size,
    c10::optional<c10::ScalarType> dtype_opt,
    c10::optional<c10::Layout> layout_opt,
    c10::optional<c10::Device> device_opt,
    c10::optional<bool> pin_memory_opt
) {
    TORCH_CHECK(!layout_opt.has_value() || layout_opt.value() == c10::Layout::Strided,
                "mydev: поддерживается только Layout::Strided");
    c10::ScalarType dtype = dtype_opt.value_or(c10::ScalarType::Float);
    (void)device_opt; (void)pin_memory_opt;
    at::Tensor t = mydev_empty_impl(size, dtype, c10::nullopt);
    if (dtype == c10::ScalarType::Float) {
        auto* p = reinterpret_cast<float*>(t.data_ptr());
        size_t n = t.numel();
        for (size_t i = 0; i < n; ++i) p[i] = 1.0f;
        return t;
    }
    TORCH_CHECK(false, "mydev_ones: поддерживается только float32");
}

// === 5g) Реализация aten::copy_ под PrivateUse1 (назначение self на mydev) ===
static at::Tensor& mydev_copy_(at::Tensor& self, const at::Tensor& src, bool non_blocking) {
    (void)non_blocking;
    TORCH_CHECK(self.scalar_type() == src.scalar_type(), "dtype mismatch in copy_");
    TORCH_CHECK(self.sizes() == src.sizes(), "size mismatch in copy_");
    TORCH_CHECK(self.is_contiguous() && src.is_contiguous(), "copy_: поддерживается только contiguous");

    const auto dst_dev = self.device().type();
    const auto src_dev = src.device().type();
    TORCH_CHECK(
        (dst_dev == c10::DeviceType::PrivateUse1 || dst_dev == c10::DeviceType::CPU) &&
        (src_dev == c10::DeviceType::PrivateUse1 || src_dev == c10::DeviceType::CPU),
        "mydev_copy_: поддерживаются только CPU<->mydev"
    );

    size_t nbytes = static_cast<size_t>(self.numel()) * at::elementSize(self.scalar_type());
    if (nbytes == 0) return self;
    void* dst_ptr = self.data_ptr();
    const void* src_ptr = src.data_ptr();
    TORCH_CHECK(dst_ptr != nullptr && src_ptr != nullptr, "copy_: null data_ptr with nonzero size");
    std::memcpy(dst_ptr, src_ptr, nbytes);
    return self;
}

// === 5h) Реализация aten::empty_like под PrivateUse1 ===
static at::Tensor mydev_empty_like(
    const at::Tensor& self,
    c10::optional<c10::ScalarType> dtype_opt,
    c10::optional<c10::Layout> layout_opt,
    c10::optional<c10::Device> device_opt,
    c10::optional<bool> pin_memory_opt,
    c10::optional<c10::MemoryFormat> memory_format_opt
) {
    TORCH_CHECK(!layout_opt.has_value() || layout_opt.value() == c10::Layout::Strided,
                "mydev: поддерживается только Layout::Strided");
    c10::ScalarType dtype = dtype_opt.value_or(self.scalar_type());
    (void)device_opt; (void)pin_memory_opt;
    return mydev_empty_impl(self.sizes(), dtype, memory_format_opt);
}

// === 5i) Реализация aten::_copy_from_and_resize под PrivateUse1 ===
// Создаёт новый тензор на mydev, размером как src, и копирует данные
static at::Tensor mydev__copy_from_and_resize(const at::Tensor& src, const at::Tensor& dst_like) {
    (void)dst_like; // используем семантику: возвращаем новый тензор-результат на mydev
    TORCH_CHECK(src.scalar_type() == c10::ScalarType::Float, "mydev__copy_from_and_resize: поддерживается только float32");

    at::Tensor out = mydev_empty_impl(src.sizes(), src.scalar_type(), c10::nullopt);
    size_t nbytes = static_cast<size_t>(src.numel()) * at::elementSize(src.scalar_type());
    if (nbytes == 0) return out;
    void* dst_ptr = out.data_ptr();
    const void* src_ptr = src.data_ptr();
    TORCH_CHECK(dst_ptr != nullptr && src_ptr != nullptr, "_copy_from_and_resize: null data_ptr with nonzero size");
    std::memcpy(dst_ptr, src_ptr, nbytes);
    return out;
}

// === 6) Реализация aten::fill_.Scalar под PrivateUse1 ===
static at::Tensor& mydev_fill_scalar_(at::Tensor& self, const at::Scalar& value) {
    TORCH_CHECK(self.device().type() == c10::DeviceType::PrivateUse1,
                "mydev_fill_: tensor не на устройстве mydev");
    TORCH_CHECK(self.scalar_type() == c10::ScalarType::Float,
                "mydev_fill_: поддерживается только float32");

    auto* data = reinterpret_cast<float*>(self.data_ptr());
    float v = value.toFloat();
    size_t n = self.numel();
    for (size_t i = 0; i < n; ++i) data[i] = v;
    return self;
}

} // namespace

// === 7) Регистрация в диспетчере ===
TORCH_LIBRARY_IMPL(aten, PrivateUse1, m) {
    m.impl("empty.memory_format", TORCH_FN(mydev_empty));
    m.impl("empty_strided", TORCH_FN(mydev_empty_strided));
    m.impl("empty_like", TORCH_FN(mydev_empty_like));
    m.impl("add.Tensor", TORCH_FN(mydev_add));
    m.impl("add.Scalar", TORCH_FN(mydev_add_scalar));
    m.impl("fill_.Scalar", TORCH_FN(mydev_fill_scalar_));
    m.impl("_copy_from", TORCH_FN(mydev__copy_from));
    m.impl("_copy_from_and_resize", TORCH_FN(mydev__copy_from_and_resize));
    m.impl("mul.Tensor", TORCH_FN(mydev_mul));
    m.impl("relu", TORCH_FN(mydev_relu));
    m.impl("relu_", TORCH_FN(mydev_relu_));
    m.impl("zeros", TORCH_FN(mydev_zeros));
    m.impl("ones", TORCH_FN(mydev_ones));
    m.impl("copy_", TORCH_FN(mydev_copy_));
}

// Общий boxed-fallback на CPU для непрореализованных операторов
namespace {
static void mydev_boxed_fallback(const c10::OperatorHandle& op, torch::jit::Stack* stack) {
    at::native::cpu_fallback(op, stack);
}
} // namespace

TORCH_LIBRARY_IMPL(_, PrivateUse1, m) {
    m.fallback(torch::CppFunction::makeFromBoxedFunction<&mydev_boxed_fallback>());
}


