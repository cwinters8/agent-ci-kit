# The same checks CI and the agents run. `make check` passing locally means
# pr-checks.yml will pass.
.PHONY: check fmt-check vet test run build image

check: fmt-check vet test

fmt-check:
	@out="$$(gofmt -l .)"; if [ -n "$$out" ]; then echo "gofmt needed:"; echo "$$out"; exit 1; fi

vet:
	go vet ./...

test:
	go test -race -count=1 ./...

run:
	go run ./cmd/server

build:
	go build -o bin/server ./cmd/server

image:
	docker build -t todoapi .
