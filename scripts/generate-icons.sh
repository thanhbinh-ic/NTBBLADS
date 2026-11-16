#!/bin/bash
# Tạo 8 PNG AppIcon từ file base64 đi kèm.
# Vì đẩy file lên GitHub qua API chỉ gửi được nội dung text (UTF-8), 8 file PNG
# nhị phân không đẩy theo cách đó được, nên repo chỉ giữ bản base64 của ảnh
# 1024x1024; script này giải mã rồi dùng sips (có sẵn trên macOS) tạo đủ 8 cỡ.
# Chạy tay trên máy Mac/Linux: bash scripts/generate-icons.sh
#
# LƯU Ý macOS (sửa 16/11/2026 sau khi build Actions lỗi exit 64):
# base64 trên macOS là bản BSD, KHÔNG nhận tên file làm đối số vị trí
# (base64 -d file.b64 -> "invalid argument"). Chỉ có 2 cách đúng:
#   - đọc từ stdin:  base64 -d < file.b64 > file.png   (chạy cả GNU lẫn BSD)
#   - dùng -i/-o:    base64 -D -i file.b64 -o file.png (chỉ BSD)
# Script dùng cách stdin để chạy được trên cả hai.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICONSET="$ROOT/App/Assets.xcassets/AppIcon.appiconset"

# Repo đẩy bằng git đã có sẵn đủ 8 PNG thì bỏ qua hẳn, không giải mã lại.
missing=0
for size in 40 58 60 80 87 120 180 1024; do
  [ -s "$ICONSET/AppIcon-$size.png" ] || missing=1
done
if [ "$missing" -eq 0 ]; then
  echo "Icons already present, skipping."
  exit 0
fi

base64 -d < "$ROOT/scripts/AppIcon-1024.png.b64" > "$ICONSET/AppIcon-1024.png"
for size in 40 58 60 80 87 120 180; do
  sips -z "$size" "$size" "$ICONSET/AppIcon-1024.png" --out "$ICONSET/AppIcon-$size.png" > /dev/null
done
echo "Icons generated in $ICONSET"
