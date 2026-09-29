// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package provider

import "core:strings"
import "core:testing"

@(test)
test_media_detect_images :: proc(t: ^testing.T) {
	kind, mime, ok := media_detect("shot.PNG")
	testing.expect(t, ok)
	testing.expect_value(t, kind, Media_Kind.Image)
	testing.expect_value(t, mime, "image/png")

	kind, mime, ok = media_detect("a/b/c.jpeg")
	testing.expect(t, ok)
	testing.expect_value(t, kind, Media_Kind.Image)
	testing.expect_value(t, mime, "image/jpeg")

	kind, mime, ok = media_detect("clip.webp")
	testing.expect(t, ok)
	testing.expect_value(t, kind, Media_Kind.Image)
	testing.expect_value(t, mime, "image/webp")
}

@(test)
test_media_detect_audio_video :: proc(t: ^testing.T) {
	kind, mime, ok := media_detect("voice.wav")
	testing.expect(t, ok)
	testing.expect_value(t, kind, Media_Kind.Audio)
	testing.expect_value(t, mime, "audio/wav")

	kind, mime, ok = media_detect("song.mp3")
	testing.expect(t, ok)
	testing.expect_value(t, kind, Media_Kind.Audio)
	testing.expect_value(t, mime, "audio/mpeg")

	kind, mime, ok = media_detect("demo.mp4")
	testing.expect(t, ok)
	testing.expect_value(t, kind, Media_Kind.Video)
	testing.expect_value(t, mime, "video/mp4")

	kind, mime, ok = media_detect("demo.webm")
	testing.expect(t, ok)
	testing.expect_value(t, kind, Media_Kind.Video)
	testing.expect_value(t, mime, "video/webm")
}

@(test)
test_media_detect_rejects_text :: proc(t: ^testing.T) {
	_, _, ok := media_detect("main.odin")
	testing.expect(t, !ok)
	_, _, ok = media_detect("notes.txt")
	testing.expect(t, !ok)
	_, _, ok = media_detect("archive.zip")
	testing.expect(t, !ok)
}

@(test)
test_media_kind_supported :: proc(t: ^testing.T) {
	openai := Provider{id = "openai"}
	testing.expect(t, media_kind_supported(&openai, "gpt-4o", .Image))

	ol := Provider{id = "ollama"}
	testing.expect(t, media_kind_supported(&ol, "qwen3-vl:8b", .Image))
	testing.expect(t, media_kind_supported(&ol, "llava:latest", .Image))
	testing.expect(t, !media_kind_supported(&ol, "llama3.1:8b", .Image))
	testing.expect(t, !media_kind_supported(&ol, "qwen3-vl:8b", .Audio))
	testing.expect(t, !media_kind_supported(&ol, "qwen3-vl:8b", .Video))

	zen := Provider{id = "opencode"}
	testing.expect(t, media_kind_supported(&zen, "gemini-3-flash", .Image))
	testing.expect(t, media_kind_supported(&zen, "gemini-3-flash", .Audio))
	testing.expect(t, media_kind_supported(&zen, "gemini-3-flash", .Video))
	testing.expect(t, !media_kind_supported(&zen, "minimax-m2.5", .Image))
	testing.expect(t, !media_kind_supported(&zen, "minimax-m2.5", .Audio))

	router := Provider{id = "openrouter"}
	testing.expect(t, media_kind_supported(&router, "google/gemini-2.5-flash", .Video))
	testing.expect(t, !media_kind_supported(&router, "deepseek/deepseek-chat", .Video))

	cb := Provider{id = "cerebras"}
	testing.expect(t, !media_kind_supported(&cb, "llama-4-scout-17b", .Audio))
	testing.expect(t, media_kind_supported(&cb, "llama-4-scout-17b", .Image))
}

@(test)
test_write_message_media_content :: proc(t: ^testing.T) {
	media := []Media_Part{
		{kind = .Image, mime = "image/png", data_b64 = "QUJD", label = "x.png"},
		{kind = .Audio, mime = "audio/mpeg", data_b64 = "REVG", label = "y.mp3"},
		{kind = .Video, mime = "video/mp4", data_b64 = "R0hJ", label = "z.mp4"},
	}
	m := Message{role = .User, content = "look", media = media}
	b := strings.builder_make(context.temp_allocator)
	write_message_json(&b, m, nil)
	body := strings.to_string(b)

	testing.expect(t, strings.contains(body, `"role":"user"`))
	testing.expect(t, strings.contains(body, `"content":[`))
	testing.expect(t, strings.contains(body, `{"type":"text","text":"look"}`))
	testing.expect(
		t,
		strings.contains(
			body,
			`{"type":"image_url","image_url":{"url":"data:image/png;base64,QUJD"}}`,
		),
	)
	testing.expect(
		t,
		strings.contains(
			body,
			`{"type":"input_audio","input_audio":{"data":"REVG","format":"mp3"}}`,
		),
	)
	testing.expect(
		t,
		strings.contains(
			body,
			`{"type":"video_url","video_url":{"url":"data:video/mp4;base64,R0hJ"}}`,
		),
	)
}

@(test)
test_write_message_media_no_text_part :: proc(t: ^testing.T) {
	media := []Media_Part{
		{kind = .Image, mime = "image/png", data_b64 = "QUJD", label = "x.png"},
	}
	m := Message{role = .User, content = "", media = media}
	b := strings.builder_make(context.temp_allocator)
	write_message_json(&b, m, nil)
	body := strings.to_string(b)
	testing.expect(t, strings.contains(body, `"content":[`))
	testing.expect(t, !strings.contains(body, `"type":"text"`))
}

@(test)
test_write_message_plain_when_no_media :: proc(t: ^testing.T) {
	m := Message{role = .User, content = "hi"}
	b := strings.builder_make(context.temp_allocator)
	write_message_json(&b, m, nil)
	body := strings.to_string(b)
	testing.expect(t, strings.contains(body, `"content":"hi"`))
	testing.expect(t, !strings.contains(body, `"content":[`))
}

@(test)
test_media_clone_destroy :: proc(t: ^testing.T) {
	src := Message{
		role = .User,
		content = strings.clone("x"),
		media = make([]Media_Part, 1),
	}
	src.media[0] = Media_Part{
		kind = .Image,
		mime = strings.clone("image/png"),
		data_b64 = strings.clone("QUJD"),
		label = strings.clone("x.png"),
	}
	clone := clone_message(src)
	testing.expect_value(t, len(clone.media), 1)
	testing.expect_value(t, clone.media[0].mime, "image/png")
	testing.expect(t, clone.media[0].data_b64 != src.media[0].data_b64 || raw_data(clone.media[0].data_b64) != raw_data(src.media[0].data_b64))
	destroy_message(clone)
	destroy_message(src)
}
