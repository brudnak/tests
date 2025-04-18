#!/bin/bash
set -e
cd $(dirname $0)/../../../../../rancher/tests


echo "Getting go rancher version "
env GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o tests/v2/validation/rancherversion ./validation/pipeline/rancherversion

echo "running rancher versions script to get the latest k8s versions"
tests/v2/validation/rancherversion