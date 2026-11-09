.PHONY: build test test-user lint clean tts-setup

# Build the Rust backend and install it to ./bin/translator
build:
	cd rust && cargo build --release
	mkdir -p bin
	cp rust/target/release/translator bin/translator

test:
	cd rust && cargo test

# Static checks (requires stylua + luacheck).
lint:
	stylua --check lua plugin after test
	luacheck lua plugin after

# User-level scenarios: real commands, real <Esc>, slow fake backend.
test-user:
	@test/user/run.sh

tts-setup:
	./scripts/tts-setup.sh

clean:
	cd rust && cargo clean
	rm -f bin/translator
