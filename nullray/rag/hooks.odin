// SPDX-License-Identifier: 0BSD
/*
Install memory put/delete hooks into the RAG index.
*/

package rag

import project_memory "nullray:memory"

install_memory_hooks :: proc() {
	project_memory.set_rag_hooks(on_memory_put, on_memory_delete)
}

on_memory_put :: proc(key, value: string) {
	_ = Index_Memory_Entry(key, value)
}

on_memory_delete :: proc(key: string) {
	_ = Remove_Memory_Key(key)
}
