// SPDX-License-Identifier: 0BSD
/*
Media attachments: extension detection, base64 file loading, and
provider/model capability heuristics for image, audio, and video parts.
*/

package provider

import "core:encoding/base64"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "nullray:constants"

media_kind_string :: proc(k: Media_Kind) -> string {
	switch k {
	case .Image:
		return "image"
	case .Audio:
		return "audio"
	case .Video:
		return "video"
	}
	return "media"
}

// Maps a file extension to a media kind and MIME type. Extensions outside
// this table fall through to plain-text attach.
media_detect :: proc(path: string) -> (kind: Media_Kind, mime: string, ok: bool) {
	ext := strings.to_lower(filepath.ext(path), context.temp_allocator)
	switch ext {
	case ".png":
		return .Image, "image/png", true
	case ".jpg", ".jpeg":
		return .Image, "image/jpeg", true
	case ".gif":
		return .Image, "image/gif", true
	case ".webp":
		return .Image, "image/webp", true
	case ".bmp":
		return .Image, "image/bmp", true
	case ".wav":
		return .Audio, "audio/wav", true
	case ".mp3":
		return .Audio, "audio/mpeg", true
	case ".flac":
		return .Audio, "audio/flac", true
	case ".ogg", ".oga":
		return .Audio, "audio/ogg", true
	case ".m4a":
		return .Audio, "audio/mp4", true
	case ".aac":
		return .Audio, "audio/aac", true
	case ".aif", ".aiff":
		return .Audio, "audio/aiff", true
	case ".mp4":
		return .Video, "video/mp4", true
	case ".webm":
		return .Video, "video/webm", true
	case ".mov":
		return .Video, "video/quicktime", true
	case ".mkv":
		return .Video, "video/x-matroska", true
	case ".avi":
		return .Video, "video/x-msvideo", true
	case ".mpg", ".mpeg":
		return .Video, "video/mpeg", true
	}
	return .Image, "", false
}

// Fallback MIME when the extension is unknown but the kind is forced.
media_mime_default :: proc(kind: Media_Kind) -> string {
	switch kind {
	case .Image:
		return "image/png"
	case .Audio:
		return "audio/mpeg"
	case .Video:
		return "video/mp4"
	}
	return "application/octet-stream"
}

media_kind_from_name :: proc(name: string) -> (Media_Kind, bool) {
	switch strings.to_lower(name, context.temp_allocator) {
	case "image", "img":
		return .Image, true
	case "audio":
		return .Audio, true
	case "video":
		return .Video, true
	}
	return .Image, false
}

// input_audio format token. OpenAI accepts wav and mp3; gateways that pass
// parts through to Gemini-style backends accept the wider set.
media_audio_format :: proc(mime: string) -> string {
	switch mime {
	case "audio/wav", "audio/x-wav", "audio/wave":
		return "wav"
	case "audio/mpeg", "audio/mp3":
		return "mp3"
	case "audio/flac":
		return "flac"
	case "audio/ogg", "application/ogg":
		return "oga"
	case "audio/mp4":
		return "m4a"
	case "audio/aac":
		return "aac"
	case "audio/aiff":
		return "aiff"
	}
	return "mp3"
}

media_enabled :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_MEDIA, context.temp_allocator); ok {
		switch strings.to_lower(v, context.temp_allocator) {
		case "0", "false", "off", "no":
			return false
		}
	}
	return true
}

media_max_bytes :: proc() -> int {
	if v, ok := os.lookup_env(constants.ENV_MEDIA_MAX, context.temp_allocator); ok {
		if n, nok := strconv.parse_int(v); nok && n > 0 {
			return n
		}
	}
	return constants.MEDIA_MAX_BYTES_DEFAULT
}

// Reads a file and returns an owned base64 Media_Part. err is a literal or
// temp string valid in the caller's scope.
media_load_file :: proc(
	path: string,
	kind: Media_Kind,
	mime: string,
	allocator := context.allocator,
) -> (part: Media_Part, err: string) {
	if !media_enabled() {
		return {}, "media disabled (NULLRAY_MEDIA)"
	}
	data, rerr := os.read_entire_file(path, context.temp_allocator)
	if rerr != nil {
		return {}, "cannot read file"
	}
	if len(data) == 0 {
		return {}, "empty file"
	}
	if len(data) > media_max_bytes() {
		return {}, fmt.tprintf(
			"file too large (%d bytes, limit %d)",
			len(data),
			media_max_bytes(),
		)
	}
	b64, berr := base64.encode(data, allocator = allocator)
	if berr != nil {
		return {}, "base64 encode failed"
	}
	return Media_Part{
			kind = kind,
			mime = strings.clone(mime, allocator),
			data_b64 = b64,
			label = strings.clone(filepath.base(path), allocator),
		},
		""
}

@(private)
VISION_MODEL_MARKERS := []string{
	"vision", "vl-", "-vl", "llava", "pixtral", "gemma3", "gemini", "claude",
	"gpt-4o", "gpt-4.1", "gpt-5", "gpt-6", "chatgpt", "o1-", "o3-", "o4-",
	"minicpm", "moondream", "internvl", "qvq", "maverick", "scout", "glm-4v",
	"glm-4.5v", "glm-5v", "kimi", "grok", "granite", "llama-4", "llama4",
	"phi-4-multimodal", "phi4-multimodal", "qwen2-vl", "qwen2.5-vl",
	"qwen3-vl", "qwen-vl", "qwen3.", "qwen-plus", "qwen-flash", "qwen-max",
	"minimax-m3", "mimo-vl", "mimo-v", "dots", "ernie", "hunyuan", "seed",
	"doubao", "aria", "nanonets", "omni", "step", "smolvlm", "molmo", "cogvlm",
}

@(private)
AUDIO_MODEL_MARKERS := []string{
	"audio", "gemini", "voxtral", "ultravox", "phi-4-multimodal",
	"phi4-multimodal", "qwen2-audio", "speech", "omni",
}

@(private)
VIDEO_MODEL_MARKERS := []string{
	"gemini", "qwen2.5-vl", "qwen3-vl", "qwen-vl", "qwen3.", "qwen-plus",
	"video",
}

@(private)
model_has_marker :: proc(model: string, markers: []string) -> bool {
	m := strings.to_lower(model, context.temp_allocator)
	for marker in markers {
		if strings.contains(m, marker) {
			return true
		}
	}
	return false
}

// Providers whose mainstream chat models all accept image parts.
@(private)
media_image_broad :: proc(id: string) -> bool {
	switch id {
	case "openai", "azure", "anthropic", "gemini", "xai":
		return true
	}
	return false
}

// Providers that plausibly forward input_audio content parts.
@(private)
media_audio_provider :: proc(id: string) -> bool {
	switch id {
	case "openai", "azure", "gemini", "opencode", "opencode-go", "openrouter":
		return true
	}
	return false
}

// video_url parts are only routed for Gemini-family models and DashScope
// qwen-vl; locals and other vendors have no documented video input.
@(private)
media_video_provider :: proc(id: string) -> bool {
	switch id {
	case "gemini", "opencode", "openrouter", "dashscope":
		return true
	}
	return false
}

// Advisory capability check. Callers should warn on false but may still send:
// model fleets change faster than name heuristics.
media_kind_supported :: proc(p: ^Provider, model: string, kind: Media_Kind) -> bool {
	id := ""
	if p != nil {
		id = p.id
	}
	switch kind {
	case .Image:
		if media_image_broad(id) {
			return true
		}
		return model_has_marker(model, VISION_MODEL_MARKERS[:])
	case .Audio:
		if !media_audio_provider(id) {
			return false
		}
		return model_has_marker(model, AUDIO_MODEL_MARKERS[:])
	case .Video:
		if !media_video_provider(id) {
			return false
		}
		return model_has_marker(model, VIDEO_MODEL_MARKERS[:])
	}
	return false
}
