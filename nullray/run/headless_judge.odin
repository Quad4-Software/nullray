// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Optional run judge (NULLRAY_JUDGE): a decision model scores whether the task
actually finished. Below threshold marks stopped=judge_fail, which
--print-strict turns into a nonzero exit.
*/

package run

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import "nullray:provider"
import "nullray:session"
import "nullray:subagent"

headless_judge_gate :: proc(
	s: ^session.Session,
	res: ^Result,
	p: ^provider.Provider,
	prompt: string,
	rt: ^subagent.Runtime,
	deadline: time.Tick,
	timeout: time.Duration,
	timeout_sec: int,
) {
	headless_judge_maybe(s, res, p, prompt)
	if res.stopped == "judge_fail" {
		headless_judge_retry(s, res, rt, prompt, deadline, timeout, timeout_sec)
	}
}

@(private)
headless_judge_maybe :: proc(s: ^session.Session, res: ^Result, p: ^provider.Provider, prompt: string) {
	jcfg := provider.judge_config_from_env(p)
	if !provider.judge_enabled(jcfg) || len(res.err) > 0 || res.stopped != "done" {
		return
	}
	final_text := last_assistant_text(s)
	prob, jok, jerr := provider.judge_score_done(&jcfg, p, prompt, final_text)
	delete(final_text)
	if jok {
		fmt.eprintfln("nullray: judge p=%.2f threshold=%.2f", prob, jcfg.threshold)
		if prob < jcfg.threshold {
			delete(res.stopped)
			res.stopped = strings.clone("judge_fail")
		}
	} else if len(jerr) > 0 {
		fmt.eprintfln("nullray: judge skipped (%s)", jerr)
		delete(jerr)
	}
}

/*
On judge_fail, climb NULLRAY_PROVIDER_FALLBACKS: nudge the session, continue
with each fallback provider, and re-judge until a pass or the ladder ends.
NULLRAY_JUDGE_RETRY=1 opts in.
*/
@(private)
headless_judge_retry :: proc(
	s: ^session.Session,
	res: ^Result,
	rt: ^subagent.Runtime,
	prompt: string,
	deadline: time.Tick,
	timeout: time.Duration,
	timeout_sec: int,
) {
	v, ok := os.lookup_env(provider.ENV_JUDGE_RETRY, context.temp_allocator)
	if !ok {
		return
	}
	switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
	case "1", "true", "yes", "on":
	case:
		return
	}
	for id in provider.provider_fallback_ids() {
		fp, okp := provider.make_provider_by_id(id)
		if !okp {
			continue
		}
		fmt.eprintfln("nullray: judge escalates to fallback provider %s", fp.id)
		session.session_push_user_media(
			s,
			"The previous attempt was judged incomplete. Continue the work and finish the task correctly, then summarize what was done.",
			nil,
		)
		session.session_start_chat(s, &fp)
		wait_session_chat(s, rt, deadline, timeout, timeout_sec, res)
		if s.busy {
			provider.provider_destroy(&fp)
			continue
		}
		stopped := s.last_stopped
		if len(stopped) == 0 {
			stopped = "done"
		}
		delete(res.stopped)
		res.stopped = strings.clone(stopped)
		headless_judge_maybe(s, res, &fp, prompt)
		provider.provider_destroy(&fp)
		if res.stopped == "done" {
			return
		}
	}
}
