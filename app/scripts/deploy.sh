#!/usr/bin/env bash
set -e

cd "$(dirname "$0")/../terraform"

terraform init
terraform apply -auto-approve
