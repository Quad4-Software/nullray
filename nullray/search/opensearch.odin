// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Generic OpenSearch backend and RSS/Atom feed parsing. OpenSearch defines
descriptors (Url templates with {searchTerms} style parameters) and XML
result conventions (RSS 2.0 / Atom 1.0); JSON results are engine-specific,
so JSON providers live in the builtin registry instead.
*/

package search

import "core:encoding/xml"
import "core:fmt"
import "core:net"
import "core:strings"
import nr_http "nullray:http"

// url is a descriptor URL, an opensearch.xml link, or a bare origin.
exec_opensearch :: proc(
	url: string,
	args: ^Args,
	allocator := context.allocator,
) -> (results: []Result, err: string, rate_limited: bool, retry_after: int) {
	desc_url := url
	if !strings.has_suffix(desc_url, ".xml") {
		desc_url = strings.trim_suffix(desc_url, "/")
		desc_url = fmt.aprintf("%s/opensearch.xml", desc_url, allocator = context.temp_allocator)
	}
	resp := nr_http.get(desc_url, {"User-Agent: nullray-search/1.0"}, 15, context.temp_allocator)
	if !resp.ok {
		return nil, strings.clone(resp.err, allocator), false, 0
	}
	if resp.status == 429 {
		return nil, strings.clone("rate limited", allocator), true, resp.retry_after
	}
	if resp.status >= 400 {
		return nil, fmt.aprintf("http %d", resp.status, allocator = allocator), false, 0
	}
	tpl, perr := opensearch_template(resp.body, context.temp_allocator)
	if perr != "" {
		return nil, strings.clone(perr, allocator), false, 0
	}
	final_url := osd_substitute(tpl, args, context.temp_allocator)
	r := nr_http.get(final_url, {"User-Agent: nullray-search/1.0", "Accept: application/rss+xml, application/atom+xml, application/xml"}, 15, context.temp_allocator)
	if !r.ok {
		return nil, strings.clone(r.err, allocator), false, 0
	}
	if r.status == 429 {
		return nil, strings.clone("rate limited", allocator), true, r.retry_after
	}
	if r.status >= 400 {
		return nil, fmt.aprintf("http %d", r.status, allocator = allocator), false, 0
	}
	res := parse_feed(r.body, args.limit > 0 ? args.limit : 5, "opensearch", allocator)
	if len(res) == 0 {
		return nil, strings.clone("no results", allocator), false, 0
	}
	return res, "", false, 0
}

// Pick the best results Url from a descriptor: RSS, Atom, then JSON, then
// HTML (which callers degrade to a composed link, not results).
@(private)
opensearch_template :: proc(body: string, allocator := context.allocator) -> (string, string) {
	doc, err := xml.parse_string(body, xml.DEFAULT_OPTIONS, "", allocator = allocator)
	if err != .None {
		return "", fmt.aprintf("descriptor parse failed: %v", err, allocator = allocator)
	}
	root := doc.elements[0]
	best_tpl := ""
	best_rank := -1
	for v in root.value {
		el_id, is_el := v.(xml.Element_ID)
		if !is_el {
			continue
		}
		el := doc.elements[el_id]
		if el.ident != "Url" {
			continue
		}
		typ, _ := xml.find_attribute_val_by_key(doc, el_id, "type")
		rel, _ := xml.find_attribute_val_by_key(doc, el_id, "rel")
		tpl, ok := xml.find_attribute_val_by_key(doc, el_id, "template")
		if !ok || rel == "suggestions" {
			continue
		}
		rank := 0
		switch typ {
		case "application/rss+xml":  rank = 3
		case "application/atom+xml": rank = 2
		case "application/json":     rank = 1
		case "text/html":            rank = 0
		}
		if rank > best_rank {
			best_rank = rank
			best_tpl = tpl
		}
	}
	if best_rank < 0 {
		return "", "no usable Url in descriptor"
	}
	return strings.clone(best_tpl, allocator), ""
}

// Substitute OpenSearch template params: {searchTerms} is required, other
// known params get values, optional {name?} collapse to empty, unknown
// required params abort.
@(private)
osd_substitute :: proc(tpl: string, args: ^Args, allocator := context.allocator) -> string {
	q := net.percent_encode(args != nil ? args.query : "", context.temp_allocator)
	limit := args != nil ? args.limit : 5
	b := strings.builder_make(allocator)
	i := 0
	for i < len(tpl) {
		c := tpl[i]
		if c == '{' {
			end := strings.index_byte(tpl[i:], '}')
			if end > 0 {
				name := tpl[i + 1 : i + end]
				optional := strings.has_suffix(name, "?")
				if optional {
					name = name[:len(name) - 1]
				}
				// Strip namespace prefix (geo:lat style).
				if ci := strings.index_byte(name, ':'); ci >= 0 {
					name = name[ci + 1:]
				}
				i += end + 1
				switch name {
				case "searchTerms":
					strings.write_string(&b, q)
				case "count":
					fmt.sbprintf(&b, "%d", limit)
				case "startIndex", "startPage":
					strings.write_string(&b, "1")
				case "language", "inputEncoding", "outputEncoding":
					strings.write_string(&b, name == "language" ? "" : "UTF-8")
				case:
					if optional {
						// empty
					} else {
						strings.write_byte(&b, '{')
						strings.write_string(&b, name)
						strings.write_byte(&b, '}')
					}
				}
				continue
			}
		}
		strings.write_byte(&b, c)
		i += 1
	}
	return strings.to_string(b)
}

// RSS 2.0 (channel/item) and Atom (feed/entry) into normalized results.
parse_feed :: proc(body: string, limit: int, provider_id: string, allocator := context.allocator) -> []Result {
	doc, err := xml.parse_string(body, xml.DEFAULT_OPTIONS, "", allocator = allocator)
	if err != .None {
		return nil
	}
	root := doc.elements[0]
	out := make([dynamic]Result, 0, allocator)
	lim := limit > 0 ? limit : 5

	if root.ident == "rss" {
		channel, found := xml.find_child_by_ident(doc, 0, "channel")
		if !found {
			return nil
		}
		for v in doc.elements[channel].value {
			item_id, is_el := v.(xml.Element_ID)
			if !is_el || doc.elements[item_id].ident != "item" {
				continue
			}
			if len(out) >= lim {
				break
			}
			append(&out, Result{
				provider = provider_id,
				title   = child_text(doc, item_id, "title", allocator),
				url     = child_text(doc, item_id, "link", allocator),
				snippet = child_text(doc, item_id, "description", allocator),
				date    = child_text(doc, item_id, "pubDate", allocator),
			})
		}
	} else if root.ident == "feed" {
		for v in root.value {
			entry_id, is_el := v.(xml.Element_ID)
			if !is_el || doc.elements[entry_id].ident != "entry" {
				continue
			}
			if len(out) >= lim {
				break
			}
			url := ""
			// Atom link: <link href="..."/>, prefer rel=alternate.
			for lv in doc.elements[entry_id].value {
				lid, is_el := lv.(xml.Element_ID)
				if !is_el || doc.elements[lid].ident != "link" {
					continue
				}
				href, has := xml.find_attribute_val_by_key(doc, lid, "href")
				if !has {
					continue
				}
				rel, _ := xml.find_attribute_val_by_key(doc, lid, "rel")
				if rel == "alternate" || len(url) == 0 {
					url = strings.clone(href, allocator)
				}
			}
			sn := child_text(doc, entry_id, "summary", allocator)
			if len(sn) == 0 {
				sn = child_text(doc, entry_id, "content", allocator)
			}
			dt := child_text(doc, entry_id, "published", allocator)
			if len(dt) == 0 {
				dt = child_text(doc, entry_id, "updated", allocator)
			}
			append(&out, Result{
				provider = provider_id,
				title   = child_text(doc, entry_id, "title", allocator),
				url     = url,
				snippet = sn,
				date    = dt,
			})
		}
	}
	return out[:]
}

@(private)
child_text :: proc(doc: ^xml.Document, parent: xml.Element_ID, ident: string, allocator := context.allocator) -> string {
	cid, found := xml.find_child_by_ident(doc, parent, ident)
	if !found {
		return ""
	}
	b := strings.builder_make(allocator)
	for v in doc.elements[cid].value {
		if s, ok := v.(string); ok {
			strings.write_string(&b, s)
		}
	}
	return strings.trim_space(strings.to_string(b))
}
