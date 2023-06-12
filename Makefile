SHELL := bash
.SHELLFLAGS := -e -c
MAKEFLAGS += --warn-undefined-variables
MAKEFLAGS += --no-builtin-rules
MKFILE_DIR := $(shell echo $(dir $(abspath $(lastword $(MAKEFILE_LIST)))) | sed 'sA/$$AA')

BUILD_DIR := $(MKFILE_DIR)/build
BUILD_ARTIFACTS_DIR := $(BUILD_DIR)/artifacts
BUILD_COVERAGE_DIR := $(BUILD_DIR)/coverage

SRC_FILES := $(shell find $(MKFILE_DIR)/cmd -type f -name "*.go")
SRC_FILES += $(shell find $(MKFILE_DIR)/internal -type f -name "*.go")
SRC_FILES += $(shell find $(MKFILE_DIR)/pkg -type f -name "*.go")

VERSION ?= $(shell git describe --tags --long --always)

DOCKER_BUILDX_FLAGS ?=
#DOCKER_PLATFORMS ?= linux/amd64,linux/arm64
DOCKER_PLATFORMS ?= linux/amd64
DOCKER_TAG ?= ghcr.io/githedgehog/k8s-tpm-device-plugin:latest

##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk commands is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

all: build

##@ Development

build: k8s-tpm-device-plugin ## Builds the k8s-tpm-device-plugin for amd64 and arm64 architectures

clean: k8s-tpm-device-plugin-clean ## Cleans the k8s-tpm-device-plugin builds

k8s-tpm-device-plugin: $(BUILD_ARTIFACTS_DIR)/k8s-tpm-device-plugin-amd64 $(BUILD_ARTIFACTS_DIR)/k8s-tpm-device-plugin-arm64

.PHONY: k8s-tpm-device-plugin-clean
k8s-tpm-device-plugin-clean:
	rm -v $(BUILD_ARTIFACTS_DIR)/k8s-tpm-device-plugin-amd64 2>/dev/null || true
	rm -v $(BUILD_ARTIFACTS_DIR)/k8s-tpm-device-plugin-arm64 2>/dev/null || true

$(BUILD_ARTIFACTS_DIR)/k8s-tpm-device-plugin-amd64: $(SRC_FILES)
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o $(BUILD_ARTIFACTS_DIR)/k8s-tpm-device-plugin-amd64 -ldflags="-w -s -X 'go.githedgehog.com/k8s-tpm-device-plugin/pkg/version.Version=$(VERSION)'" ./cmd/k8s-tpm-device-plugin

$(BUILD_ARTIFACTS_DIR)/k8s-tpm-device-plugin-arm64: $(SRC_FILES)
	CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -o $(BUILD_ARTIFACTS_DIR)/k8s-tpm-device-plugin-arm64 -ldflags="-w -s -X 'go.githedgehog.com/k8s-tpm-device-plugin/pkg/version.Version=$(VERSION)'" ./cmd/k8s-tpm-device-plugin

# Use this target only for local linting. In CI we use a dedicated github action
.PHONY: lint
lint: ## Runs golangci-lint (NOTE: target for local development only, used through github action in CI)
	golangci-lint run --verbose ./...

test: test-race test-cover ## Runs golang unit tests twice: for code coverage, and the second time with race detector

.PHONY: test-race
test-race: ## Runs golang unit tests with race detector
	@echo "Running tests with race detector..."
	go test -race ./cmd/... ./pkg/...
	@echo

.PHONY: test-cover
test-cover: ## Runs golang unit tests and generates code coverage information
	@echo "Running tests for code coverage..."
	go test -cover -covermode=count -coverprofile $(BUILD_COVERAGE_DIR)/coverage.profile ./cmd/... ./pkg/...
	go tool cover -func=$(BUILD_COVERAGE_DIR)/coverage.profile -o=$(BUILD_COVERAGE_DIR)/coverage.out
	go tool cover -html=$(BUILD_COVERAGE_DIR)/coverage.profile -o=$(BUILD_COVERAGE_DIR)/coverage.html
	@echo
	@echo -n "Total Code Coverage: "; tail -n 1 $(BUILD_COVERAGE_DIR)/coverage.out | awk '{ print $$3 }'
	@echo

##@ Build

.PHONY: docker-build
docker-build: ## Builds the application in a docker container and creates a docker image
	docker buildx build \
		-f $(MKFILE_DIR)/docker/Dockerfile \
		-t $(DOCKER_TAG) \
		--progress=plain \
		--build-arg APPVERSION=$(VERSION) \
		--build-arg TARGETHOSTARCH=x86_64 \
		--build-arg MKIMAGEARCH=x86_64 \
		--build-arg GPG_PUBKEY=$(GPG_PUBKEY) \
		--platform=$(DOCKER_PLATFORMS) $(DOCKER_BUILDX_FLAGS) \
		. 2>&1