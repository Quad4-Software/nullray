// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Text normalization and similarity helpers for the hybrid loop detector:
a shared normalized form for call sets and tool results, a token-set
Jaccard for the fuzzy signal, cosine over vectors, the hashed-trigram
semantic fallback, and the production embed bridge.
*/

package agent

import "core:hash"
import "core:math"
import "core:strings"
import "nullray:provider"

// Cap on normalized text kept per observation for similarity work.
LOOP_NORM_CAP :: 512
// Buckets for the hashed-trigram semantic fallback vector.
LOOP_HASH_DIM :: 64

// Trivial tool acks that must not feed the stagnation signal on their own.
// Path-bearing write/edit successes ("ok wrote path (N bytes)") stay in.
loop_result_is_trivial :: proc(norm: string) -> bool {
	switch norm {
	case "ok", "ok fuzzy", "done", "true", "false", "yes", "no":
		return true
	}
	return false
}

// Mutating tools: fuzzy similarity over JSON structure is noisy; Exact and
// stagnation still cover stuck rewrites and stuck errors.
loop_calls_are_mutators :: proc(calls: []provider.Tool_Call) -> bool {
	if len(calls) == 0 {
		return false
	}
	for c in calls {
		switch c.name {
		case "write_file", "edit_file", "apply_edits", "multi_edit":
		case:
			return false
		}
	}
	return true
}

// Lowercase alnum runs joined by single spaces, capped. JSON punctuation,
// quoting, and path separators collapse, so near-identical calls normalize
// together.
loop_norm_text :: proc(s: string, allocator := context.temp_allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	pending_space := false
	for i in 0 ..< len(s) {
		if strings.builder_len(b) >= LOOP_NORM_CAP {
			break
		}
		c := s[i]
		alnum := (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
		if alnum {
			if pending_space && strings.builder_len(b) > 0 {
				strings.write_byte(&b, ' ')
			}
			pending_space = false
			if c >= 'A' && c <= 'Z' {
				c += 32
			}
			strings.write_byte(&b, c)
		} else {
			pending_space = true
		}
	}
	return strings.to_string(b)
}

loop_norm_calls :: proc(calls: []provider.Tool_Call, allocator := context.temp_allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	for c in calls {
		strings.write_string(&b, c.name)
		strings.write_byte(&b, ' ')
		strings.write_string(&b, c.arguments)
		strings.write_byte(&b, ' ')
	}
	return loop_norm_text(strings.to_string(b), allocator)
}

// Jaccard over whitespace token sets. Pure surface similarity for the
// fuzzy signal.
loop_token_jaccard :: proc(a, b: string) -> f64 {
	if len(a) == 0 || len(b) == 0 {
		return 0
	}
	if a == b {
		return 1
	}
	aset := make(map[string]struct{}, context.temp_allocator)
	for t in strings.fields(a, context.temp_allocator) {
		aset[t] = {}
	}
	inter := 0
	bset := make(map[string]struct{}, context.temp_allocator)
	for t in strings.fields(b, context.temp_allocator) {
		bset[t] = {}
		if t in aset {
			inter += 1
		}
	}
	u := len(aset) + len(bset) - inter
	if u == 0 {
		return 0
	}
	return f64(inter) / f64(u)
}

loop_cosine :: proc(a, b: []f32) -> f64 {
	n := min(len(a), len(b))
	if n == 0 {
		return 0
	}
	dot, na, nb := f64(0), f64(0), f64(0)
	for i in 0 ..< n {
		dot += f64(a[i]) * f64(b[i])
		na += f64(a[i]) * f64(a[i])
		nb += f64(b[i]) * f64(b[i])
	}
	if na == 0 || nb == 0 {
		return 0
	}
	return dot / (math.sqrt(na) * math.sqrt(nb))
}

// Pure semantic fallback: hashed character-trigram bag over the
// normalized text. Catches paraphrase-shaped repeats without a model.
loop_hash_embed :: proc(text: string, user: rawptr, allocator := context.allocator) -> []f32 {
	_ = user
	v := make([]f32, LOOP_HASH_DIM, allocator)
	norm := loop_norm_text(text, context.temp_allocator)
	n := len(norm)
	if n == 0 {
		return v
	}
	if n < 3 {
		h := hash.fnv64a(transmute([]byte)norm)
		v[h % LOOP_HASH_DIM] += 1
		return v
	}
	for i in 0 ..< n - 2 {
		h := hash.fnv64a(transmute([]byte)norm[i:i + 3])
		v[h % LOOP_HASH_DIM] += 1
	}
	return v
}

// Embed bridge for the production semantic path. Vectors are copied out
// under the caller allocator and the response body is destroyed inside a
// matching allocator context so the temp heap never frees its storage.
Loop_Embed_Ctx :: struct {
	prov:  ^provider.Provider,
	model: string,
}

loop_embed_bridge :: proc(text: string, user: rawptr, allocator := context.allocator) -> []f32 {
	ctx := cast(^Loop_Embed_Ctx)user
	if ctx == nil || ctx.prov == nil || ctx.prov.embed == nil {
		return nil
	}
	prev := context.allocator
	context.allocator = allocator
	res := provider.provider_embed_texts(ctx.prov, ctx.model, []string{text}, allocator)
	out: []f32
	if res.ok && len(res.vectors) > 0 && len(res.vectors[0]) > 0 {
		out = make([]f32, len(res.vectors[0]), allocator)
		copy(out, res.vectors[0])
	}
	provider.destroy_embed_response(&res)
	context.allocator = prev
	return out
}
