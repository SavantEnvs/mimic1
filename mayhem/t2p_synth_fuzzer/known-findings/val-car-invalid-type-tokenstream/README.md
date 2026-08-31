# Finding: `val_car()` aborts on an invalid-typed `cst_val` while building the tokenizer's charclass table

**Found by:** `t2p_synth_fuzzer` (in-process libFuzzer), fork mode, ~40s over the seed corpus.
**Status:** upstream defect, unfixed. Not guarded in the harness (it is a crash, not a hang — see
`docs/netnew-worker-prompt.md` §6b: crashes are normal libFuzzer findings and must not be masked).

## Reproduce

```
mayhem/build.sh   # builds t2p_synth_fuzzer-standalone
ASAN_OPTIONS=detect_leaks=0 ./t2p_synth_fuzzer-standalone \
  mayhem/t2p_synth_fuzzer/known-findings/val-car-invalid-type-tokenstream/repro1
```

Both `repro1` and `repro2` reproduce the identical crash (same PC / same assertion message);
`repro2` is the smaller of the two (41 bytes) and is kept as a second confirmation.

`repro2` bytes (`od -c`): `e.g. i.e.00th -3.14 +\001\026` followed by 15 `A` bytes and `ton`.

## Symptom

The process prints the library's own internal error message and calls `exit(-1)` (see
`include/cst_error.h`'s `cst_error()` macro — `DIE_ON_ERROR` is not defined in this build, so the
non-abort branch runs: `longjmp` if a jump target is registered, else `exit(-1)`; here none is
registered inside the harness, so the whole process exits):

```
VAL: tried to access car in -1 typed val
```

No ASan/UBSan report is produced — this is not a classic out-of-bounds write, it is application-level
misuse of a `cst_val` whose type tag is `-1` (an invalid/never-initialized sentinel).

## Where

```
val_car (src/utils/cst_val.c:182)
  <- set_charclass_table_symbol (src/utils/cst_tokenstream.c:210)
       <- set_charclass_table (src/utils/cst_tokenstream.c:420)
            <- set_charclasses (src/utils/cst_tokenstream.c:449)
                 <- new_tokenstream (src/utils/cst_tokenstream.c:513)
                      <- ts_open_string (src/utils/cst_tokenstream.c:568)
                           <- default_tokenization (src/synth/cst_synth.c:214)
                                <- apply_synth_module / apply_synth_method / utt_synth
                                     <- mimic_do_synth -> mimic_synth_text
```

`set_charclass_table_symbol()` walks `cst_utf8_explode(symbols)` — `symbols` here is one of the
FIXED constant charclass strings (`whitespace=" \t\n\r"`, `prepunctuation`, `postpunctuation`, …)
that `new_tokenstream()` passes on every call, not attacker-controlled text. That the walk fails
only for certain inputs means the `cst_val` list `cst_utf8_explode()` returns has already been
corrupted (or an earlier `cst_val` was freed/reused incorrectly) by the time this constant-string
setup runs for the SECOND tokenstream `default_tokenization()` opens while processing the
malformed sentence above (dense abbreviation/ordinal text — "e.g. i.e. ... th -3.14" — followed
by two raw control bytes 0x01 0x16). The actual origin of the bad `cst_val` (most likely in the
number/ordinal expansion path exercised just before the crash, per the fork-mode coverage log
showing `en_exp_roman` newly covered immediately prior) was not root-caused further within the
time budget of this port — this record captures the reproducer and crash site, not a fix.

## Impact

A crash (`exit(-1)`, not a hang) on a plain text string — no external voice/lexicon file, no
audio synthesis, pure front-end text processing. Reachable from any caller of `mimic_synth_text()`
/ `mimic_text_to_wave()`, i.e. every consumer of this library's public synthesis API.

## Suggested next step (not applied — see additive-only rule)

Root-cause the `cst_val` corruption (start with the ordinal/abbreviation expansion path in
`lang/usenglish/us_expand.c`, which the fork-mode coverage log shows newly exercised immediately
before both crashes). Once identified, either fix the corruption at its source or have
`cst_utf8_explode()`/`set_charclass_table_symbol()` fail soft (return an error) instead of the
current `cst_error()` hard-exit — but that upstream fix is out of scope for this integration and is
NOT applied here (this repo's `mayhem` branch must stay purely additive over upstream; see
`PORTING.md`'s "Instrumenting an UPSTREAM source file" note for how a durable fix would be shipped
without touching the committed upstream file, if this were pursued).
