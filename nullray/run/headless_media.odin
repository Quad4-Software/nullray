// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Print-mode media attachment loading.
*/

package run

Media_Input :: struct {
	path: string,
	kind: string,
}

import "core:fmt"
import "core:strings"
import "nullray:provider"

/*
Load --image/--audio/--video/--media paths into owned Media_Part slices.
Errors are owned by the caller's allocator.
*/
load_media_parts :: proc(
	inputs: []Media_Input,
	p: ^provider.Provider,
) -> (parts: []provider.Media_Part, err: string) {
	out := make([dynamic]provider.Media_Part, context.allocator)
	failed := ""
	defer delete(failed)
	for mi in inputs {
		kind: provider.Media_Kind
		mime := ""
		if len(mi.kind) > 0 {
			k, kok := provider.media_kind_from_name(mi.kind)
			if !kok {
				failed = fmt.tprintf("bad media kind %s", mi.kind)
				break
			}
			kind = k
			_, mime, _ = provider.media_detect(mi.path)
			if len(mime) == 0 {
				mime = provider.media_mime_default(kind)
			}
		} else {
			k, m, ok := provider.media_detect(mi.path)
			if !ok {
				failed = fmt.tprintf("unrecognized media type %s", mi.path)
				break
			}
			kind, mime = k, m
		}
		part, lerr := provider.media_load_file(mi.path, kind, mime)
		if len(lerr) > 0 {
			failed = fmt.tprintf("%s: %s", mi.path, lerr)
			break
		}
		if !provider.media_kind_supported(p, p.default_model, kind) {
			fmt.eprintf(
				"nullray: warning: %s may not accept %s input\n",
				p.default_model,
				provider.media_kind_string(kind),
			)
		}
		append(&out, part)
	}
	if len(failed) > 0 {
		provider.destroy_media_parts_owned(out[:])
		return nil, strings.clone(failed)
	}
	return out[:], ""
}
