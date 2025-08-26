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
    TORCH_CHECK(b.device().type() == c10::DeviceType::PrivateUse1,
                "mydev_add: tensor 'b' не на устройстве mydev");
    TORCH_CHECK(a.scalar_type() == c10::ScalarType::Float,
                "mydev_add: поддерживается только float32");
    TORCH_CHECK(b.scalar_type() == a.scalar_type(),
                "mydev_add: dtype должен совпадать");
    TORCH_CHECK(a.sizes() == b.sizes(),
                "mydev_add: требуем одинаковые размеры без broadcasting");

    at::Tensor out = mydev_empty_impl(a.sizes(), a.scalar_type(), c10::nullopt);

    auto* ap = reinterpret_cast<float*>(a.data_ptr());
    auto* bp = reinterpret_cast<float*>(b.data_ptr());
    auto* op = reinterpret_cast<float*>(out.data_ptr());

    float alpha_f = alpha.toFloat();
    size_t n = a.numel();
    for (size_t i = 0; i < n; ++i) {
        op[i] = ap[i] + alpha_f * bp[i];
    }
    return out;
}

// === 5c) Реализация aten::_copy_from под PrivateUse1 (поддерживаем копирование -> CPU) ===
static at::Tensor mydev__copy_from(const at::Tensor& self, const at::Tensor& dst, bool non_blocking) {
    TORCH_CHECK(self.device().type() == c10::DeviceType::PrivateUse1,
                "mydev__copy_from: source tensor не на устройстве mydev");
    (void)non_blocking;

    if (dst.device().type() == c10::DeviceType::CPU) {
        TORCH_CHECK(self.scalar_type() == dst.scalar_type(), "dtype mismatch in _copy_from");
        TORCH_CHECK(self.sizes() == dst.sizes(), "size mismatch in _copy_from");
        TORCH_CHECK(self.is_contiguous() && dst.is_contiguous(), "_copy_from: поддерживается только contiguous");

        size_t nbytes = static_cast<size_t>(self.numel()) * at::elementSize(self.scalar_type());
        std::memcpy(dst.data_ptr(), self.data_ptr(), nbytes);
        return dst;
    }

    TORCH_CHECK(false, "mydev__copy_from: поддерживается только копирование в CPU");
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
    m.impl("add.Tensor", TORCH_FN(mydev_add));
    m.impl("fill_.Scalar", TORCH_FN(mydev_fill_scalar_));
    m.impl("_copy_from", TORCH_FN(mydev__copy_from));
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


