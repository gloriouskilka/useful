#!/usr/bin/env bash
set -Eeuo pipefail

echo "[debug] Activating venv if present"
if [[ -x "/opt/venv/bin/activate" ]]; then
  # shellcheck disable=SC1091
  source /opt/venv/bin/activate
fi

echo "[debug] Python: $(command -v python || true)"
python --version || true
pip --version || true

echo "[debug] Env summary"
echo "  VIRTUAL_ENV=${VIRTUAL_ENV:-}"
echo "  PYTHONPATH=${PYTHONPATH:-}"
echo "  TT_METAL_HOME=${TT_METAL_HOME:-}"
echo "  Torch_DIR=${Torch_DIR:-}"

echo "[debug] pip list (torch/ttnn)"
pip list | grep -E "^(torch(-ttnn)?|torchvision|ttnn|torch_ttnn_cpp_extension)" || true

echo "[debug] pip show"
for pkg in torch torch-ttnn torchvision ttnn torch_ttnn_cpp_extension; do
  echo "-- $pkg --"; pip show "$pkg" || true; echo
done

echo "[debug] Running Python diagnostics"
python "$(dirname "$0")/ttnn_debug.py" || true

echo "[debug] Done"


