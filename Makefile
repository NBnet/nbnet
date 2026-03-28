CARGO := cargo

.PHONY: all fmt lint build test bench-nbnet run clean check doc

all: fmt lint build test

fmt:
	$(CARGO) fmt --all

lint:
	$(CARGO) clippy --workspace --all-targets -- -D warnings

build:
	$(CARGO) build --workspace

test:
	$(CARGO) test --workspace

check:
	$(CARGO) check --workspace --all-targets

bench-nbnet:
	$(CARGO) run --release -p nbnet-node --bin bench-nbnet

run:
	$(CARGO) run --release -p nbnet-node --bin nb -- node

doc:
	$(CARGO) doc --workspace --no-deps --open

clean:
	$(CARGO) clean

update:
	$(CARGO) update
