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

mkdir -p builds

# -------------------------------
# Write implant code to file
# -------------------------------
cat > implant_standalone.go << 'EOF'
package main

import (
	"fmt"
	"runtime"
	"time"
)

func main() {
	accessKey := "REPLACE_ACCESS_KEY"
	secretKey := "REPLACE_SECRET_KEY"

	fmt.Println("[*] X-Ray C2 Standalone Implant")
	fmt.Println("    OS:", runtime.GOOS)
	fmt.Println("    Arch:", runtime.GOARCH)
	fmt.Println("    AWS Access Key:", accessKey)
	fmt.Println("    AWS Secret Key:", secretKey)
	fmt.Println("")

	for {
		fmt.Printf("[*] Heartbeat from %s/%s at %s\n", runtime.GOOS, runtime.GOARCH, time.Now().Format(time.RFC3339))
		time.Sleep(10 * time.Second)
	}
}
EOF

# Embed credentials
sed -i.bak "s#REPLACE_ACCESS_KEY#$ACCESS_KEY#g" implant_standalone.go
sed -i.bak "s#REPLACE_SECRET_KEY#$SECRET_KEY#g" implant_standalone.go
rm -f implant_standalone.go.bak

# -------------------------------
# Build for macOS (Intel)
# -------------------------------
echo ""
echo "[*] Building macOS (amd64) implant..."
GOOS=darwin GOARCH=amd64 go build -ldflags="-s -w" -o builds/aws-cli-macos-amd64 implant_standalone.go
if [ $? -eq 0 ]; then
    echo "[+] Built: builds/aws-cli-macos-amd64 ($(ls -lh builds/aws-cli-macos-amd64 | awk '{print $5}'))"
else
    echo "[-] macOS amd64 build failed"
    exit 1
fi

# -------------------------------
# Build for macOS (ARM64)
# -------------------------------
echo ""
echo "[*] Building macOS (arm64) implant..."
GOOS=darwin GOARCH=arm64 go build -ldflags="-s -w" -o builds/aws-cli-macos-arm64 implant_standalone.go
if [ $? -eq 0 ]; then
    echo "[+] Built: builds/aws-cli-macos-arm64 ($(ls -lh builds/aws-cli-macos-arm64 | awk '{print $5}'))"
else
    echo "[-] macOS arm64 build failed"
    exit 1
fi

# -------------------------------
# Build for Windows (Intel)
# -------------------------------
echo ""
echo "[*] Building Windows (amd64) implant..."
GOOS=windows GOARCH=amd64 go build -ldflags="-s -w -H=windowsgui" -o builds/aws-cli.exe implant_standalone.go
if [ $? -eq 0 ]; then
    echo "[+] Built: builds/aws-cli.exe ($(ls -lh builds/aws-cli.exe | awk '{print $5}'))"
else
    echo "[-] Windows build failed"
    exit 1
fi

# -------------------------------
# Cleanup
# -------------------------------
echo ""
echo "[*] Cleaning up..."
rm -f implant_standalone.go

echo ""
echo "====================================="
echo "BUILD COMPLETE."
echo ""
echo "  - builds/aws-cli-macos-amd64"
echo "  - builds/aws-cli-macos-arm64"
echo "  - builds/aws-cli.exe"
echo "====================================="
