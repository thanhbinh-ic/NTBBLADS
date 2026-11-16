#!/bin/bash
# Tạo 8 PNG AppIcon từ file base64 đi kèm.
# Vì đẩy file lên GitHub qua API chỉ gửi được nội dung text (UTF-8), 8 file PNG
# nhị phân không đẩy theo cách đó được, nên repo chỉ giữ bản base64 của ảnh
# 1024x1024; script này giải mã rồi dùng sips (có sẵn trên macOS) tạo đủ 8 cỡ.
# Chạy tay trên máy Mac/Linux: bash scripts/generate-icons.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICONSET="$ROOT/App/Assets.xcassets/AppIcon.appiconset"
base64 -d "$ROOT/scripts/AppIcon-1024.png.b64" > "$ICONSET/AppIcon-1024.png"
for size in 40 58 60 80 87 120 180; do
  sips -z "$size" "$size" "$ICONSET/AppIcon-1024.png" --out "$ICONSET/AppIcon-$size.png" > /dev/null
done
echo "Icons generated in $ICONSET"
