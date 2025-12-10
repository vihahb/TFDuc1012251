#!/bin/bash
set -euo pipefail

########################################
# Các hàm hỗ trợ thông báo
########################################
info() {
  echo "🔧 $1"
}

success() {
  echo "✅ $1"
}

warning() {
  echo "⚠️ $1"
}

error() {
  echo "❌ $1" >&2
}

########################################
# Hàm hỏi Y/N
########################################
ask_yes_no() {
  local prompt="$1"
  local answer
  read -r -p "$prompt (Y/N): " answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    return 0
  else
    return 1
  fi
}

########################################
# --- Các hàm chung cho cả 2 kịch bản ---
########################################

# Bước 1: Cập nhật Podfile (FirebaseFirestore)
update_podfile() {
  local podfile="ios/Podfile"
  if [[ -f "$podfile" ]]; then
    if grep -q "pod 'FirebaseFirestore'" "$podfile"; then
      info "Podfile đã có dòng 'FirebaseFirestore'. Bỏ qua cập nhật."
    else
      info "Cập nhật Podfile với FirebaseFirestore..."
      sed -i '' '1i\
pod '"'"'FirebaseFirestore'"'"', :git => '"'"'https://github.com/invertase/firestore-ios-sdk-frameworks.git'"'"', :tag => '"'"'12.4.0'"'"'
' "$podfile"
      success "Podfile đã được cập nhật."
    fi
  else
    warning "File Podfile không tồn tại tại $podfile."
  fi
}

# Bước 2: Cập nhật pubspec.yaml (các dependency khác)
update_pubspec() {
  local pubspec="pubspec.yaml"
  if [[ -f "$pubspec" ]]; then
    if grep -q "flutter_inappwebview:" "$pubspec"; then
      info "pubspec.yaml đã có dependency mong muốn. Bỏ qua cập nhật."
    else
      info "Cập nhật pubspec.yaml với dependency mới..."
      awk '
        BEGIN { inserted = 0; inFlutter = 0; }
        {
          if ($0 ~ /^[[:space:]]*flutter:[[:space:]]*$/) {
            inFlutter = 1;
          }
          print $0;
          if (inFlutter && inserted == 0 && $0 ~ /^[[:space:]]*sdk:[[:space:]]*flutter/) {
            print "  flutter_inappwebview: ^6.1.5";
            print "  firebase_core: ^4.1.0";
            print "  firebase_analytics: ^12.0.1";
            print "  modal_bottom_sheet: ^3.0.0";
            print "  cloud_firestore: ^6.0.1";
            print "  shared_preferences: ^2.2.0";
            print "  dio: ^5.9.0";
            inserted = 1;
            inFlutter = 0;
          }
        }
      ' "$pubspec" > tmp_pubspec.yaml && mv tmp_pubspec.yaml "$pubspec"
      success "pubspec.yaml đã được cập nhật."
    fi
  else
    warning "File pubspec.yaml không tồn tại tại $pubspec."
  fi
}

# Bước 3: Cập nhật Minimum Deployment Target trong Xcode project
update_deployment_target() {
  local xcodeproj="ios/Runner.xcodeproj/project.pbxproj"
  if [[ -f "$xcodeproj" ]]; then
    if grep -q "IPHONEOS_DEPLOYMENT_TARGET = 15.6;" "$xcodeproj"; then
      info "Minimum Deployment Target đã là 15.6. Bỏ qua cập nhật."
    else
      info "Cập nhật Minimum Deployment Target thành 15.6..."
      sed -i '' -E "s/(IPHONEOS_DEPLOYMENT_TARGET = )([0-9\.]+)(;)/\115.6\3/g" "$xcodeproj"
      success "Minimum Deployment Target đã được cập nhật."
    fi
  else
    warning "File Xcode project không tồn tại tại $xcodeproj."
  fi
}

# Bước 4 & 5: Cập nhật Bundle Identifier và tắt Automatically Manage Signing
update_bundle_identifier_and_signing() {
  local xcodeproj="ios/Runner.xcodeproj/project.pbxproj"
  if [[ -f "$xcodeproj" ]]; then
    read -r -p "Nhập Bundle ID cho iOS (thêm tiền tố 'dn.' nếu cần): " bundle_id
    if [[ -z "$bundle_id" ]]; then
      info "Không có Bundle ID được nhập. Bỏ qua cập nhật."
    else
      info "Cập nhật Bundle Identifier thành: $bundle_id"
      sed -i '' -E "s/(PRODUCT_BUNDLE_IDENTIFIER = )[^;]+;/\1${bundle_id};/g" "$xcodeproj"
      success "Bundle Identifier đã được cập nhật."
    fi
    info "Tắt Automatically Manage Signing (chuyển CODE_SIGN_STYLE và ProvisioningStyle thành Manual)..."
    sed -i '' -E "s/(CODE_SIGN_STYLE[[:space:]]*=[[:space:]]*)Automatic;/\1Manual;/g" "$xcodeproj"
    sed -i '' -E "s/(ProvisioningStyle[[:space:]]*=[[:space:]]*)Automatic;/\1Manual;/g" "$xcodeproj"
    success "Signing đã được cập nhật thành Manual."
  else
    warning "File Xcode project không tồn tại tại $xcodeproj. Bỏ qua cập nhật Bundle Identifier và Signing."
  fi
}

# Bước 6: Cập nhật CFBundleDisplayName trong Info.plist
update_display_name() {
  local plist="ios/Runner/Info.plist"
  if [[ -f "$plist" ]]; then
    read -r -p "Nhập CFBundleDisplayName (Display Name): " display_name
    if [[ -z "$display_name" ]]; then
      info "Không có Display Name được nhập. Bỏ qua cập nhật."
    else
      info "Cập nhật CFBundleDisplayName thành: $display_name"
      sed -i '' -E "/<key>CFBundleDisplayName<\/key>/{n;s|<string>[^<]+</string>|<string>${display_name}</string>|;}" "$plist"
      success "CFBundleDisplayName đã được cập nhật."
    fi
  else
    warning "File Info.plist không tồn tại tại $plist."
  fi
}

########################################
# --- Các hàm riêng cho bước icon ---
########################################

# Hàm cập nhật dependency flutter_launcher_icons vào pubspec.yaml (nếu chưa có)
update_flutter_launcher_icons_dependency() {
  local pubspec="pubspec.yaml"
  if grep -q "flutter_launcher_icons:" "$pubspec"; then
    info "Dependency flutter_launcher_icons đã có trong pubspec.yaml."
  else
    info "Thêm dependency flutter_launcher_icons vào pubspec.yaml..."
    if grep -q "^dev_dependencies:" "$pubspec"; then
      sed -i '' '/^dev_dependencies:/a\
  flutter_launcher_icons: ^0.9.2
' "$pubspec"
    else
      echo "" >> "$pubspec"
      echo "dev_dependencies:" >> "$pubspec"
      echo "  flutter_launcher_icons: ^0.9.2" >> "$pubspec"
    fi
    success "Dependency flutter_launcher_icons đã được thêm."
    info "Chạy 'flutter pub get' để cập nhật dependency..."
    flutter pub get
  fi
}

# Dành cho kịch bản 1: Ứng dụng mới (hỏi trước khi ghi đè cấu hình flutter_icons)
setup_icons_new() {
  local icon_dir="assets/iconapp"
  local pubspec="pubspec.yaml"

  if [[ ! -d "$icon_dir" ]]; then
    mkdir -p "$icon_dir"
    success "Đã tạo thư mục $icon_dir."
  else
    info "Thư mục $icon_dir đã tồn tại."
  fi

  echo "Vui lòng copy file icon của bạn vào thư mục $icon_dir (chỉ cần 1 file). Nhấn Enter khi đã xong..."
  read -r

  local files=("$icon_dir"/*)
  if [[ ${#files[@]} -eq 0 ]]; then
    warning "Không tìm thấy file icon nào trong $icon_dir. Bỏ qua bước tạo icon."
    return
  elif [[ ${#files[@]} -gt 1 ]]; then
    warning "Phát hiện nhiều hơn 1 file trong $icon_dir. Vui lòng chỉ có 1 file icon. Bỏ qua bước tạo icon."
    return
  fi

  local icon_file="${files[0]}"
  info "File icon được tìm thấy: $icon_file"

  if grep -q "flutter_icons:" "$pubspec"; then
    if ask_yes_no "Cấu hình flutter_icons đã tồn tại. Bạn có muốn ghi đè cấu hình và cập nhật icon mới?"; then
      info "Ghi đè cấu hình flutter_icons với icon mới..."
      awk 'BEGIN {skip=0}
           /^flutter_icons:/ { skip=1; next }
           skip==1 && /^[[:space:]]/ { next }
           { skip=0; print }' "$pubspec" > tmp_pubspec.yaml && mv tmp_pubspec.yaml "$pubspec"
      cat <<EOF >> "$pubspec"

flutter_icons:
  android: false
  ios: true
  image_path: "$icon_file"
EOF
      success "Cấu hình flutter_launcher_icons đã được ghi đè trong pubspec.yaml."
      info "Chạy 'flutter pub get' để cập nhật dependency..."
      flutter pub get
    else
      info "Bỏ qua ghi đè cấu hình flutter_icons."
    fi
  else
    info "Thêm cấu hình flutter_launcher_icons vào pubspec.yaml..."
    cat <<EOF >> "$pubspec"

flutter_icons:
  android: false
  ios: true
  image_path: "$icon_file"
EOF
    success "Cấu hình flutter_launcher_icons đã được thêm vào pubspec.yaml."
    info "Chạy 'flutter pub get' để cập nhật dependency..."
    flutter pub get
  fi

  info "Chạy flutter_launcher_icons để tạo icon..."
  flutter pub run flutter_launcher_icons:main
  success "Icon đã được tạo thành công."
}

# Dành cho kịch bản 2: Update ứng dụng (luôn ghi đè cấu hình flutter_icons)
setup_icons_update() {
  local icon_dir="assets/iconapp"
  local pubspec="pubspec.yaml"

  if [[ ! -d "$icon_dir" ]]; then
    mkdir -p "$icon_dir"
    success "Đã tạo thư mục $icon_dir."
  else
    info "Thư mục $icon_dir đã tồn tại."
  fi

  echo "Vui lòng copy file icon của bạn vào thư mục $icon_dir (chỉ cần 1 file). Nhấn Enter khi đã xong..."
  read -r

  local files=("$icon_dir"/*)
  if [[ ${#files[@]} -eq 0 ]]; then
    warning "Không tìm thấy file icon nào trong $icon_dir. Bỏ qua bước tạo icon."
    return
  elif [[ ${#files[@]} -gt 1 ]]; then
    warning "Phát hiện nhiều hơn 1 file trong $icon_dir. Vui lòng chỉ có 1 file icon. Bỏ qua bước tạo icon."
    return
  fi

  local icon_file="${files[0]}"
  info "File icon được tìm thấy: $icon_file"

  info "Ghi đè luôn cấu hình flutter_icons với icon mới..."
  awk 'BEGIN {skip=0}
       /^flutter_icons:/ { skip=1; next }
       skip==1 && /^[[:space:]]/ { next }
       { skip=0; print }' "$pubspec" > tmp_pubspec.yaml && mv tmp_pubspec.yaml "$pubspec"
  cat <<EOF >> "$pubspec"

flutter_icons:
  android: false
  ios: true
  image_path: "$icon_file"
EOF
  success "Cấu hình flutter_launcher_icons đã được cập nhật trong pubspec.yaml."
  info "Chạy 'flutter pub get' để cập nhật dependency..."
  flutter pub get

  info "Chạy flutter_launcher_icons để tạo icon..."
  flutter pub run flutter_launcher_icons:main
  success "Icon đã được tạo thành công."
}

########################################
# --- Main: Chọn kịch bản và thực hiện các bước ---
########################################

echo "============================================"
echo "BẮT ĐẦU THỰC HIỆN CÀI ĐẶT VÀ CẤU HÌNH"
echo "============================================"

echo "Chọn kịch bản:"
echo "  1. Ứng dụng mới (thiết lập từ đầu)"
echo "  2. Update ứng dụng (chỉ ghi đè icon và cập nhật Display Name)"
read -r -p "Nhập số (1 hoặc 2): " mode

if [[ "$mode" == "1" ]]; then
  info "Chạy kịch bản Ứng dụng mới..."
  if ask_yes_no "Bạn có muốn tạo icon cho iOS bằng flutter_launcher_icons không?"; then
    update_flutter_launcher_icons_dependency
    setup_icons_new
  else
    info "Bỏ qua tạo icon."
  fi
  update_podfile
  update_pubspec
  update_deployment_target
  if ask_yes_no "Bạn có muốn cập nhật Bundle Identifier và tắt Automatically Manage Signing không?"; then
    update_bundle_identifier_and_signing
    if ask_yes_no "Bạn có muốn cập nhật CFBundleDisplayName (Display Name) không?"; then
      update_display_name
    else
      info "Bỏ qua cập nhật Display Name."
    fi
  else
    info "Bỏ qua cập nhật Bundle Identifier, Signing và Display Name."
  fi
elif [[ "$mode" == "2" ]]; then
  info "Chạy kịch bản Update ứng dụng..."
  setup_icons_update
  update_display_name
else
  error "Không hợp lệ. Vui lòng chạy lại và chọn 1 hoặc 2."
  exit 1
fi

echo "=> Tự động hoá hoàn tất!"
