#!/bin/bash
set -e

echo "🦀 Building Rust library..."
cargo build --release

APP="TimeTrack3.app"
APP_DIR="$APP/Contents"
MACOS_DIR="$APP_DIR/MacOS"
LIB_DIR="$MACOS_DIR/lib"

echo "📦 Creating app bundle..."
rm -rf "$APP"
mkdir -p "$MACOS_DIR" "$LIB_DIR"

echo "📝 Writing Info.plist..."
cat > "$APP_DIR/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>TimeTrack3</string>
    <key>CFBundleIdentifier</key>
    <string>com.timetrack3.app</string>
    <key>CFBundleVersion</key>
    <string>0.1.0</string>
    <key>CFBundleExecutable</key>
    <string>TimeTrack3</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>10.15</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
</dict>
</plist>
EOF

echo "🔗 Copying Rust library..."
cp target/release/libtimetrack3.a "$LIB_DIR/"

echo "🏗 Compiling Swift..."
swiftc \
    -o "$MACOS_DIR/TimeTrack3" \
    -L "$LIB_DIR" \
    -ltimetrack3 \
    -Xlinker -rpath -Xlinker "@executable_path/lib" \
    swift/App.swift

echo ""
echo "✅ Done! Launch with:"
echo "   open TimeTrack3.app"