// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
RSS 2.0 and Atom feed parsing for fetch_rss.

Keeps a lightweight tag scanner (not a full XML stack). Returns a plain
text digest the agent can scan and then fetch_url individual links.
*/

package tools

import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

RSS_DEFAULT_ITEMS :: 10
RSS_MAX_ITEMS :: 30
RSS_SNIPPET_CHARS :: 180

Rss_Item :: struct {
	title:   string,
	link:    string,
	summary: string,
	published: string,
}

Rss_Feed :: struct {
	title: string,
	link:  string,
	items: [dynamic]Rss_Item,
}

rss_looks_like :: proc(body: string) -> bool {
	probe := body
	if len(probe) > 4096 {
		probe = probe[:4096]
	}
	lower := strings.to_lower(probe, context.temp_allocator)
	if strings.contains(lower, "<rss") || strings.contains(lower, "<feed") {
		return true
	}
	if strings.contains(lower, "<channel") && strings.contains(lower, "<item") {
		return true
	}
	if strings.contains(lower, "xmlns=\"http://www.w3.org/2005/atom\"") {
		return true
	}
	return false
}

// Parse RSS 2.0 or Atom into owned feed fields under allocator.
rss_parse :: proc(body: string, max_items: int, allocator := context.allocator) -> (feed: Rss_Feed, ok: bool) {
	if !rss_looks_like(body) {
		return {}, false
	}
	n := max_items
	if n <= 0 {
		n = RSS_DEFAULT_ITEMS
	}
	if n > RSS_MAX_ITEMS {
		n = RSS_MAX_ITEMS
	}
	feed.items = make([dynamic]Rss_Item, 0, n, allocator)
	lower := strings.to_lower(body, context.temp_allocator)

	// Channel / feed title + link from the outer envelope.
	if ch := rss_first_tag_region(body, lower, "channel"); len(ch) > 0 {
		feed.title = rss_child_text(ch, "title", allocator)
		feed.link = rss_child_text(ch, "link", allocator)
	} else if fd := rss_first_tag_region(body, lower, "feed"); len(fd) > 0 {
		feed.title = rss_child_text(fd, "title", allocator)
		feed.link = rss_atom_link_href(fd, allocator)
	}

	// Collect item/entry blocks in document order.
	search_body := body
	search_lower := lower
	offset := 0
	for len(feed.items) < n {
		item_tag := "item"
		idx := strings.index(search_lower, "<item")
		entry_idx := strings.index(search_lower, "<entry")
		if idx < 0 || (entry_idx >= 0 && entry_idx < idx) {
			idx = entry_idx
			item_tag = "entry"
		}
		if idx < 0 {
			break
		}
		abs := offset + idx
		region := rss_tag_region_from(body, lower, abs, item_tag)
		if len(region) == 0 {
			// Skip past this open tag and continue.
			offset = abs + len(item_tag) + 1
			if offset >= len(body) {
				break
			}
			search_body = body[offset:]
			search_lower = lower[offset:]
			continue
		}
		it: Rss_Item
		it.title = rss_child_text(region, "title", allocator)
		if item_tag == "entry" {
			it.link = rss_atom_link_href(region, allocator)
			it.summary = rss_child_text(region, "summary", allocator)
			if len(it.summary) == 0 {
				it.summary = rss_child_text(region, "content", allocator)
			}
			it.published = rss_child_text(region, "updated", allocator)
			if len(it.published) == 0 {
				it.published = rss_child_text(region, "published", allocator)
			}
		} else {
			it.link = rss_child_text(region, "link", allocator)
			it.summary = rss_child_text(region, "description", allocator)
			if len(it.summary) == 0 {
				it.summary = rss_child_text(region, "content:encoded", allocator)
			}
			it.published = rss_child_text(region, "pubdate", allocator)
			if len(it.published) == 0 {
				it.published = rss_child_text(region, "dc:date", allocator)
			}
		}
		it.summary = rss_plain_snip(it.summary, RSS_SNIPPET_CHARS, allocator)
		append(&feed.items, it)
		// Advance past this region.
		offset = abs + len(region)
		if offset >= len(body) {
			break
		}
		search_body = body[offset:]
		search_lower = lower[offset:]
	}
	ok = len(feed.title) > 0 || len(feed.items) > 0
	return feed, ok
}

rss_destroy :: proc(feed: ^Rss_Feed) {
	if feed == nil {
		return
	}
	delete(feed.title)
	delete(feed.link)
	for it in feed.items {
		delete(it.title)
		delete(it.link)
		delete(it.summary)
		delete(it.published)
	}
	delete(feed.items)
	feed^ = {}
}

rss_format :: proc(feed: Rss_Feed, source_url: string, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	fmt.sbprintf(&b, "feed=%s\n", source_url)
	if len(feed.title) > 0 {
		fmt.sbprintf(&b, "title=%s\n", feed.title)
	}
	if len(feed.link) > 0 {
		fmt.sbprintf(&b, "link=%s\n", feed.link)
	}
	fmt.sbprintf(&b, "items=%d\n", len(feed.items))
	for it, i in feed.items {
		fmt.sbprintf(&b, "\n[%d] %s\n", i + 1, len(it.title) > 0 ? it.title : "(no title)")
		if len(it.link) > 0 {
			fmt.sbprintf(&b, "    %s\n", it.link)
		}
		if len(it.published) > 0 {
			fmt.sbprintf(&b, "    %s\n", it.published)
		}
		if len(it.summary) > 0 {
			fmt.sbprintf(&b, "    %s\n", it.summary)
		}
	}
	if len(feed.items) > 0 {
		strings.write_string(&b, "\nfetch_url <item-url> for full article text.\n")
	}
	return strings.to_string(b)
}

// --- internals -----------------------------------------------------------

@(private)
rss_first_tag_region :: proc(body, lower, name: string) -> string {
	needle := fmt.tprintf("<%s", name)
	idx := strings.index(lower, needle)
	if idx < 0 {
		return ""
	}
	return rss_tag_region_from(body, lower, idx, name)
}

@(private)
rss_tag_region_from :: proc(body, lower: string, start: int, name: string) -> string {
	if start < 0 || start >= len(body) {
		return ""
	}
	// Find end of opening tag.
	gt := strings.index_byte(body[start:], '>')
	if gt < 0 {
		return ""
	}
	open_end := start + gt
	// Self-closing?
	if open_end > start && body[open_end - 1] == '/' {
		return body[start:open_end + 1]
	}
	close := fmt.tprintf("</%s>", name)
	rest_l := lower[open_end + 1:]
	cidx := strings.index(rest_l, close)
	if cidx < 0 {
		return ""
	}
	end := open_end + 1 + cidx + len(close)
	if end > len(body) {
		end = len(body)
	}
	return body[start:end]
}

@(private)
rss_child_text :: proc(region, name: string, allocator := context.allocator) -> string {
	lower := strings.to_lower(region, context.temp_allocator)
	needle := fmt.tprintf("<%s", name)
	idx := strings.index(lower, needle)
	if idx < 0 {
		return strings.clone("", allocator)
	}
	// Ensure we matched a real tag boundary (not titleX).
	after := idx + len(needle)
	if after < len(region) {
		c := region[after]
		if c != '>' && c != ' ' && c != '\t' && c != '\n' && c != '\r' && c != '/' {
			// Keep searching for a later match.
			rest := region[after:]
			rest_l := lower[after:]
			sub := rss_child_text(rest, name, allocator)
			return sub
		}
	}
	gt := strings.index_byte(region[idx:], '>')
	if gt < 0 {
		return strings.clone("", allocator)
	}
	content_start := idx + gt + 1
	if content_start > 0 && region[content_start - 2] == '/' {
		// empty element <link ... />
		return strings.clone("", allocator)
	}
	close := fmt.tprintf("</%s>", name)
	rest_l := lower[content_start:]
	cidx := strings.index(rest_l, close)
	if cidx < 0 {
		return strings.clone("", allocator)
	}
	raw := region[content_start:content_start + cidx]
	return rss_decode_text(raw, allocator)
}

@(private)
rss_atom_link_href :: proc(region: string, allocator := context.allocator) -> string {
	lower := strings.to_lower(region, context.temp_allocator)
	// Prefer rel="alternate", else first href.
	search := lower
	offset := 0
	best := ""
	for {
		idx := strings.index(search, "<link")
		if idx < 0 {
			break
		}
		abs := offset + idx
		rest := region[abs:]
		gt := strings.index_byte(rest, '>')
		if gt < 0 {
			break
		}
		tag := rest[:gt + 1]
		tag_l := strings.to_lower(tag, context.temp_allocator)
		href, hok := html_tag_attr(tag, "href")
		if hok && len(href) > 0 {
			rel, rok := html_tag_attr(tag, "rel")
			if rok && strings.contains(strings.to_lower(rel, context.temp_allocator), "alternate") {
				return rss_decode_text(href, allocator)
			}
			if len(best) == 0 {
				best = href
			}
			// bare <link>href</link> (RSS-in-Atom hybrid)
			if !strings.contains(tag_l, "href=") {
				inner := rss_child_text(region[abs:], "link", allocator)
				if len(inner) > 0 {
					return inner
				}
			}
		} else if !hok {
			// Text-content form.
			inner := rss_child_text(region[abs:], "link", allocator)
			if len(inner) > 0 && len(best) == 0 {
				best = inner
			}
		}
		offset = abs + gt + 1
		if offset >= len(region) {
			break
		}
		search = lower[offset:]
	}
	if len(best) > 0 {
		return rss_decode_text(best, allocator)
	}
	return strings.clone("", allocator)
}

@(private)
rss_decode_text :: proc(s: string, allocator := context.allocator) -> string {
	// Strip CDATA wrappers and simple tags, decode entities.
	raw := strings.trim_space(s)
	if strings.has_prefix(raw, "<![CDATA[") {
		inner := raw[len("<![CDATA["):]
		if end := strings.index(inner, "]]>"); end >= 0 {
			raw = inner[:end]
		} else {
			raw = inner
		}
	}
	// If still contains tags, strip lightly.
	if strings.contains(raw, "<") {
		raw = rss_strip_tags(raw, context.temp_allocator)
	}
	b: strings.Builder
	strings.builder_init(&b, allocator)
	i := 0
	for i < len(raw) {
		if raw[i] == '&' {
			ent, n := html_decode_entity(raw[i:])
			if n > 0 {
				strings.write_string(&b, ent)
				i += n
				continue
			}
		}
		if raw[i] == '\r' {
			i += 1
			continue
		}
		if raw[i] == '\n' || raw[i] == '\t' {
			strings.write_byte(&b, ' ')
			i += 1
			continue
		}
		strings.write_byte(&b, raw[i])
		i += 1
	}
	out := strings.to_string(b)
	trimmed := strings.trim_space(out)
	if len(trimmed) == len(out) {
		return out
	}
	cloned := strings.clone(trimmed, allocator)
	delete(out)
	return cloned
}

@(private)
rss_strip_tags :: proc(s: string, allocator := context.temp_allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	i := 0
	for i < len(s) {
		if s[i] == '<' {
			end := strings.index_byte(s[i:], '>')
			if end < 0 {
				break
			}
			i += end + 1
			continue
		}
		strings.write_byte(&b, s[i])
		i += 1
	}
	return strings.to_string(b)
}

@(private)
rss_plain_snip :: proc(s: string, max_chars: int, allocator := context.allocator) -> string {
	t := strings.trim_space(s)
	if len(t) == 0 {
		return strings.clone("", allocator)
	}
	// Collapse runs of spaces.
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	prev_sp := false
	i := 0
	for i < len(t) {
		r, w := utf8.decode_rune_in_string(t[i:])
		if w <= 0 {
			break
		}
		i += w
		if unicode.is_space(r) {
			if !prev_sp {
				strings.write_byte(&b, ' ')
				prev_sp = true
			}
			continue
		}
		strings.write_string(&b, fmt.tprintf("%r", r))
		prev_sp = false
	}
	out := strings.trim_space(strings.to_string(b))
	if max_chars > 0 && len(out) > max_chars {
		return strings.clone(out[:max_chars], allocator)
	}
	return strings.clone(out, allocator)
}
