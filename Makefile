.PHONY: build test clean

# Build the Rust backend and install it to ./bin/translator
build:
	cd rust && cargo build --release
	mkdir -p bin
	cp rust/target/release/translator bin/translator

test:
	cd rust && cargo test

clean:
	cd rust && cargo clean
	rm -f bin/translator
