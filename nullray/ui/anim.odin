/*
Frame animations for status and busy indicators.
*/

package ui

import "core:time"
import "nullray:constants"

Spinner :: struct {
	frames: []string,
	idx:    int,
	last:   time.Tick,
}

SPINNER_BRAILLE := []string{"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}
SPINNER_DOTS := []string{".  ", ".. ", "...", " ..", "  .", "   "}
SPINNER_BAR := []string{"▏", "▎", "▍", "▌", "▋", "▊", "▉", "█", "▉", "▊", "▋", "▌", "▍", "▎"}

spinner_init :: proc(frames: []string = SPINNER_BRAILLE) -> Spinner {
	return Spinner{frames = frames, idx = 0, last = time.tick_now()}
}

spinner_frame :: proc(s: ^Spinner) -> string {
	if len(s.frames) == 0 {
		return "*"
	}
	now := time.tick_now()
	if time.tick_diff(s.last, now) >= time.Duration(constants.SPINNER_FRAME_MS) * time.Millisecond {
		s.idx = (s.idx + 1) % len(s.frames)
		s.last = now
	}
	return s.frames[s.idx]
}

// Pulse 0..1..0 over period_ms for accent fades.
anim_pulse :: proc(period_ms: int = 1600) -> f32 {
	if period_ms <= 0 {
		return 0
	}
	ms := int(time.to_unix_nanoseconds(time.now()) / 1_000_000)
	half := period_ms / 2
	if half <= 0 {
		return 0
	}
	phase := ms % period_ms
	if phase < half {
		return f32(phase) / f32(half)
	}
	return 1 - f32(phase - half) / f32(half)
}
