# User-level tests

Scenario tests that drive the plugin the way a user does: `:Translate*`
commands, real `<Esc>` presses through the mapping layer, and a deliberately
slow fake backend so a request is still in flight when the key is pressed.

```sh
make test-user          # or: test/user/run.sh
```

Each scenario runs in its own `nvim --headless -u NONE` process and prints one
`PASS`/`FAIL` line per assertion group. The runner exits non-zero if any line
starts with `FAIL`.

| Scenario | Covers |
| --- | --- |
| `s1_buffered_esc` | Esc while a buffered request runs (spinner only) |
| `s2_stream_before_result` | Esc before the first streaming engine returns |
| `s3_stream_mid_stream` | Esc while the result window is already open |
| `s4_restore_user_map` | the user's own `<Esc>` mapping is restored (string and callback variants) |
| `s5_replace_esc` | Esc during `:TranslateR` leaves the buffer untouched |
| `s6_inline_esc` | Esc cancels a whole `:TranslateV` batch, rerun still works |
| `s7_success_path` | successful request keeps the window; Esc closes it and unbinds |
| `s8_cancel_command` | `:TranslateCancel` cancels, and is a no-op when idle |
| `s9_cancel_key_disabled` | `cancel_key = false` binds nothing, request still completes |
| `s10_triple_esc` | repeated Esc is harmless, normal Esc still works afterwards |

`fake_backend.py` understands `--stream`, `--batch`, `--stdin` and emits one
`T:<text>` translation per input line. `SLOW_DELAY` (default 3) is the initial
latency, `SLOW_STAGGER` (default 0) the gap between engines/lines.
