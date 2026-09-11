/*
 * mayhem/t2p_synth_fuzzer.c — libFuzzer harness for mimic1's text-to-speech FRONT END.
 *
 * Drives the exact same code path as the upstream `t2p` tool (main/t2p_main.c): build the
 * built-in "no_wave" US-English voice (usenglish text analysis + the CMU lexicon/letter-to-
 * sound rules; no external voice/lexicon FILE is loaded -- the language data is compiled in)
 * and run mimic_synth_text() over the fuzzer-controlled bytes. mimic_synth_text() runs the
 * FULL linguistic front end -- tokenization, part-of-speech tagging, the CMU lexicon lookup +
 * letter-to-sound rules for out-of-vocabulary words, phrasing, and intonation -- the exact
 * surface that parses untrusted TEXT input. The voice's wave_synth_func is a no-op (matching
 * upstream's own `cmu_us_no_wave`), so no waveform DSP/audio synthesis ever runs: the harness
 * stays fast and fully deterministic, and every byte of the input is fair game for the fuzzer.
 *
 * No file I/O: bytes come only from the fuzzer, and the built-in voice needs no on-disk
 * voice/lexicon file (see register_cmu_us_no_wave() in the upstream t2p tool this mirrors).
 */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "cst_features.h"
#include "cst_lexicon.h"
#include "cst_utterance.h"
#include "cst_val.h"
#include "cst_voice.h"
#include "mimic.h"

#include "usenglish.h"
#include "cmu_lex.h"

static cst_voice *g_voice = NULL;

static cst_utterance *no_wave_synth(cst_utterance *u)
{
    return u;
}

static cst_voice *register_cmu_us_no_wave(void)
{
    cst_voice *v = new_voice();
    cst_lexicon *lex;

    if (!v)
        return NULL;

    v->name = "no_wave_voice";

    usenglish_init(v);
    feat_set_string(v->features, "name", "cmu_us_no_wave");

    lex = cmu_lex_init();
    feat_set(v->features, "lexicon", lexicon_val(lex));

    feat_set_float(v->features, "int_f0_target_mean", 95.0);
    feat_set_float(v->features, "int_f0_target_stddev", 11.0);
    feat_set_float(v->features, "duration_stretch", 1.1);

    feat_set(v->features, "postlex_func", uttfunc_val(lex->postlex));
    feat_set(v->features, "wave_synth_func", uttfunc_val(&no_wave_synth));

    return v;
}

int LLVMFuzzerInitialize(int *argc, char ***argv)
{
    (void) argc;
    (void) argv;
    mimic_init();
    g_voice = register_cmu_us_no_wave();
    return 0;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    /* The text front end is not meant to process multi-megabyte inputs; bound the work per
     * exec so a single huge input cannot itself look like a hang. */
    if (size > 65536)
        return 0;
    if (!g_voice)
        return 0;

    char *text = (char *) malloc(size + 1);
    if (!text)
        return 0;
    memcpy(text, data, size);
    text[size] = '\0';

    cst_utterance *u = mimic_synth_text(text, g_voice);
    if (u)
        delete_utterance(u);

    free(text);
    return 0;
}
