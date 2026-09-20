import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch, MagicMock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from simlab import analysis, campaigns, config, policies, runner, storage
from simlab.engine import Engine


class LabTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.config = config.load("combined", ["time.days=2", "time.social_rounds=2", "time.action_rounds=2"])

    def tearDown(self):
        self.temp.cleanup()

    def run_new(self, cfg=None, steps=None):
        path = runner.new_run(self.root, cfg or self.config)
        result = runner.drive(path, self.root, max_steps=steps)
        return path, result

    def test_config_rejects_unknown_and_invalid(self):
        for change in ({"invented": 1}, {"seed": True}, {"time": {"days": 0}}, {"memory": {"strategy": "telepathy"}}, {"economy": {"bill": float("nan")}}, {"inference": {"endpoint": "http://localhost"}}, {"mechanics": {"alliances": "yes"}}, {"inference": {"max_attempts": 0}}, {"inference": {"fallback_models": ["a", "a"]}}, {"inference": {"fallback_models": [config.DEFAULT["inference"]["model"]]}}, {"inference": {"fallback_models": [""]}}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                config.validate(config.merge(config.DEFAULT, change))
        bad = copy.deepcopy(self.config)
        bad["actors"][1]["id"] = bad["actors"][0]["id"]
        with self.assertRaises(ValueError):
            config.validate(bad)

    def test_all_scenarios(self):
        for name in ("bargaining", "alliances", "mediation", "combined"):
            path, result = self.run_new(config.load(name, ["time.days=1"]))
            self.assertEqual(result["status"], "horizon")
            self.assertTrue(result["metrics"]["accounting_balanced"])
            self.assertTrue(runner.replay(path)["verified"])

    def test_resume_matches_uninterrupted(self):
        whole, _ = self.run_new()
        split, _ = self.run_new(steps=7)
        runner.drive(split, self.root)
        self.assertEqual(storage.load_checkpoint(whole)[1], storage.load_checkpoint(split)[1])

    def test_crash_after_response_reuses_response(self):
        whole, _ = self.run_new()
        interrupted = runner.new_run(self.root, self.config)
        def crash(where):
            if where == "response":
                raise RuntimeError("synthetic crash")
        with self.assertRaises(RuntimeError):
            runner.drive(interrupted, self.root, crash_hook=crash)
        with patch("simlab.policies.scripted", side_effect=AssertionError("Must reuse durable response")):
            runner.drive(interrupted, self.root, max_steps=1)
        runner.drive(interrupted, self.root)
        self.assertEqual(storage.load_checkpoint(whole)[1], storage.load_checkpoint(interrupted)[1])

    def test_crash_after_apply_does_not_double_spend(self):
        whole, _ = self.run_new()
        interrupted = runner.new_run(self.root, self.config)
        calls = [0]
        def crash(where):
            if where == "applied":
                calls[0] += 1
                if calls[0] == 8:
                    raise RuntimeError("after apply")
        with self.assertRaises(RuntimeError):
            runner.drive(interrupted, self.root, crash_hook=crash)
        runner.drive(interrupted, self.root)
        self.assertEqual(storage.load_checkpoint(whole)[1], storage.load_checkpoint(interrupted)[1])

    def test_torn_journal_and_uncertain_request(self):
        path = runner.new_run(self.root, self.config)
        def crash(where):
            if where == "request": raise RuntimeError("crash")
        with self.assertRaises(RuntimeError):
            runner.drive(path, self.root, crash_hook=crash)
        with (path / "journal.jsonl").open("ab") as stream:
            stream.write(b'{"partial":')
        runner.drive(path, self.root, max_steps=1)
        self.assertTrue(list(path.glob("torn-*.bin")))
        self.assertTrue(any(r["kind"] == "uncertain_request" for r in storage.journal(path)))

    def test_branch_preserves_parent(self):
        path, _ = self.run_new(steps=4)
        before = (path / "journal.jsonl").read_bytes()
        child = runner.branch(path, self.root, 2, ["memory.strategy=\"none\""])
        runner.drive(child, self.root)
        self.assertEqual(before, (path / "journal.jsonl").read_bytes())
        self.assertTrue(runner.replay(child)["verified"])
        self.assertEqual(storage.read(child / "manifest.json")["parent"]["checkpoint"], 2)

    def test_branch_choice_and_invalid_migration(self):
        path, _ = self.run_new(steps=1)
        with self.assertRaises(ValueError):
            runner.branch(path, self.root, overrides=["actors.0.cash=900"])
        child = runner.branch(path, self.root, 0, choice=0)
        runner.drive(child, self.root, max_steps=1)
        self.assertTrue(runner.replay(child)["verified"])

    def test_private_information_isolated(self):
        with Engine(ROOT) as engine:
            state = engine.call("new", config=self.config, seed=1)["state"]
            obs = engine.call("observe", state=state, config=self.config, actor="blue")["observation"]
        self.assertNotIn("actors", obs)
        self.assertNotIn("red:savings", obs["actor"]["knowledge"])
        self.assertFalse(any(e["kind"] == "income" and e["actor"] != "blue" for e in obs["events"]))

    def test_context_memory_ablation(self):
        with Engine(ROOT) as engine:
            state = engine.call("new", config=self.config, seed=1)["state"]
            obs = engine.call("observe", state=state, config=self.config)["observation"]
        cfg = copy.deepcopy(self.config)
        cfg["memory"]["strategy"] = "none"
        projected = policies.context(obs, cfg)
        self.assertEqual(projected["events"], [])
        self.assertEqual(projected["memory_summary"], [])
        self.assertEqual(projected["actor"]["relationships"], {})

    def test_malformed_policy_falls_back(self):
        path = runner.new_run(self.root, self.config)
        with patch("simlab.policies.scripted", return_value=({"choice": True, "speech": "", "channel": "public"}, {"rng": 1, "decisions": 1})):
            result = runner.drive(path, self.root, max_steps=1)
        self.assertEqual(result["metrics"]["usage"]["fallbacks"], 1)
        self.assertTrue(runner.replay(path)["verified"])

    def test_stop_and_lock(self):
        path = runner.new_run(self.root, self.config)
        with storage.lock(path):
            with self.assertRaises(RuntimeError):
                runner.drive(path, self.root, max_steps=1)
        storage.atomic(path / "STOP", {})
        self.assertEqual(runner.drive(path, self.root)["reason"], "stop_requested")

    def test_branch_fallback_rate_excludes_inherited_failures(self):
        parent = runner.new_run(self.root, self.config)
        malformed = ({"choice": True, "speech": "", "channel": "public"}, {"rng": 1, "decisions": 1})
        with patch("simlab.policies.scripted", return_value=malformed):
            runner.drive(parent, self.root, max_steps=2)
        child = runner.branch(parent, self.root)
        empty = analysis.summarize(child)
        self.assertIsNone(empty["fallback_rate"])
        self.assertEqual(empty["inherited_fallbacks"], 2)
        runner.drive(child, self.root, max_steps=2)
        with patch("simlab.policies.scripted", return_value=malformed):
            result = runner.drive(child, self.root, max_steps=1)["metrics"]
        self.assertEqual(result["usage"]["fallbacks"], 3)
        self.assertEqual(result["segment_fallbacks"], 1)
        self.assertEqual(result["segment_decisions"], 3)
        self.assertEqual(result["inherited_fallbacks"], 2)
        self.assertAlmostEqual(result["fallback_rate"], 1 / 3)
        self.assertTrue(runner.replay(child)["verified"])

    def test_checkpoint_corruption_rejected(self):
        path, _ = self.run_new(steps=1)
        data = storage.read(path / "checkpoints/000001.json")
        data["payload"]["state"]["heat"] += 1
        storage.atomic(path / "checkpoints/000001.json", data)
        with self.assertRaises(ValueError):
            runner.replay(path)

    def test_source_snapshot_corruption_rejected(self):
        path, _ = self.run_new(steps=1)
        with (path / "source/src/shared/Lab.luau").open("a") as file:
            file.write("-- changed")
        with self.assertRaises(ValueError):
            runner.replay(path)

    def test_call_and_cost_budgets(self):
        payload = {"usage": {"calls": 100, "known_cost_usd": 0}}
        self.assertEqual(runner.budget_reason(payload, self.config, 0, True), "call_budget")
        self.assertEqual(runner.budget_reason(payload, self.config, 1000, False), "time_budget")
        cfg = copy.deepcopy(self.config)
        cfg["inference"].update(pricing_known=True, input_usd_per_million=1000)
        payload["usage"]["calls"] = 0
        self.assertEqual(runner.budget_reason(payload, cfg, 0, True), "cost_budget")

    def test_nvidia_timeout_and_secret_redaction(self):
        inference = self.config["inference"]
        with patch.dict("os.environ", NVIDIA_API_KEY="synthetic-key"), patch("simlab.policies.rate_limit"), patch("urllib.request.build_opener") as opener:
            opener.return_value.open.side_effect = TimeoutError()
            result = policies.nvidia({}, inference, self.root)
            self.assertEqual(result["error"], "TimeoutError")
            opener.return_value.open.side_effect = None
            response = MagicMock()
            response.status = 200
            response.read.return_value = json.dumps({"choices": [{"finish_reason": "stop", "message": {"content": json.dumps({"speech": "synthetic-key"})}}]}).encode()
            opener.return_value.open.return_value.__enter__.return_value = response
            result = policies.nvidia({}, inference, self.root)
            self.assertNotIn("synthetic-key", json.dumps(result))

    def test_evaluation_rejects_fabricated_evidence(self):
        report = {"findings": [{"dimension": "memory", "observation": "x", "interpretation": "x", "event_ids": ["e999"], "confidence": "low", "counterevidence": "none", "next_test": "ablation"}]}
        with self.assertRaises(ValueError):
            analysis.validate_findings(report, [{"id": "e1"}])
        path, _ = self.run_new(steps=1)
        self.assertTrue(Path(analysis.evaluate(path, self.root)["report"]).exists())

    def test_paired_campaign_and_resume(self):
        result = campaigns.search(self.root, {"scenario": "bargaining", "space": {"time.days": [1]}, "max_runs": 2, "workers": 2})
        self.assertEqual(result["completed"], 2)
        repeated = campaigns.search(self.root, resume=result["campaign"])
        self.assertEqual(repeated["completed"], 2)
        comparison = storage.read(Path(result["campaign"]) / "comparison.json")
        self.assertEqual(comparison["run_count"], 2)

    def test_holdout_is_disjoint(self):
        with self.assertRaises(ValueError):
            campaigns.validate({"seeds": [1], "holdout_seeds": [1]})
        with self.assertRaises(ValueError):
            campaigns.validate({"schema": True})

    def test_supervisor_failed_call_is_reserved(self):
        result = campaigns.search(self.root, {"scenario": "bargaining", "space": {"time.days": [1]}, "max_runs": 1})
        directory = Path(result["campaign"])
        cfg = storage.read(directory / "config.json")
        cfg.update(max_runs=2, strategy="adaptive", supervisor="codex")
        storage.atomic(directory / "config.json", cfg)
        with patch("simlab.campaigns.supervisor", side_effect=RuntimeError("interrupted supervisor")):
            with self.assertRaises(RuntimeError):
                campaigns.search(self.root, resume=directory, live=True)
        self.assertEqual(storage.read(directory / "state.json")["role_calls"]["supervisor"], 1)

    def test_command_adapters_preserve_malformed_output(self):
        for provider in ("codex", "claude"):
            with self.subTest(provider=provider), patch("shutil.which", return_value="fake-agent"), patch("simlab.policies.subprocess.run") as run:
                run.return_value = MagicMock(returncode=0, stdout="not-json", stderr="diagnostic")
                result = policies.command_agent(provider, "prompt", ROOT / "experiments/rubrics/strategic-social-v1.json", self.root / "missing.json", self.root)
                self.assertEqual(result["error"], "malformed_agent_output")
                self.assertEqual(result["stdout"], "not-json")
                self.assertNotIn("NVIDIA_API_KEY", run.call_args.kwargs["env"])

    def test_provider_catalog_checked_before_inference(self):
        with patch.dict("os.environ", NVIDIA_API_KEY="synthetic-key"), patch("simlab.policies.rate_limit"), patch("urllib.request.build_opener") as opener:
            response = MagicMock(status=200, headers={"x-ratelimit-limit-requests": "30"})
            response.read.return_value = json.dumps({"data": [{"id": self.config["inference"]["model"]}]}).encode()
            opener.return_value.open.return_value.__enter__.return_value = response
            destination = self.root / "launch.json"
            result = policies.preflight(self.config["inference"], self.root, destination)
            self.assertTrue(result["available"])
            self.assertNotIn("synthetic-key", destination.read_text())
            response.read.return_value = b'{"data": []}'
            with self.assertRaises(RuntimeError):
                policies.preflight(self.config["inference"], self.root, destination)
            self.assertEqual(storage.read(destination)["error"], "model_not_in_catalog")

    def test_rate_limiter_reserves_future_slots(self):
        inference = self.config["inference"]
        with patch("simlab.policies.time.time", return_value=1000), patch("simlab.policies.time.sleep") as sleep:
            policies.rate_limit(self.root, inference)
            policies.rate_limit(self.root, inference)
            self.assertEqual(sleep.call_args.args[0], 2)

    def test_http_429_is_recorded_without_retry(self):
        import urllib.error
        with patch.dict("os.environ", NVIDIA_API_KEY="synthetic-key"), patch("simlab.policies.rate_limit"), patch("urllib.request.build_opener") as opener:
            opener.return_value.open.side_effect = urllib.error.HTTPError("https://example.invalid", 429, "throttled", {}, None)
            result = policies.nvidia({}, self.config["inference"], self.root)
            self.assertEqual(result["http_status"], 429)
            self.assertEqual(opener.return_value.open.call_count, 1)

    def test_context_budget_and_disk_pause(self):
        cfg = copy.deepcopy(self.config)
        cfg["limits"]["min_free_mb"] = 1000000
        path = runner.new_run(self.root, cfg)
        with patch("simlab.storage.shutil.disk_usage") as usage:
            usage.return_value.free = 1
            result = runner.drive(path, self.root)
        self.assertEqual(result["reason"], "disk_pressure")
        self.assertEqual(result["checkpoint"], 0)

    def test_http_503_preserves_bounded_redacted_diagnostics(self):
        import io
        import urllib.error
        body = b'synthetic-key unavailable ' + b'x' * 70000
        with patch.dict("os.environ", NVIDIA_API_KEY="synthetic-key"), patch("simlab.policies.rate_limit"), patch("urllib.request.build_opener") as opener:
            opener.return_value.open.side_effect = urllib.error.HTTPError(
                "https://example.invalid", 503, "unavailable",
                {"retry-after": "30", "set-cookie": "unrelated"}, io.BytesIO(body))
            result = policies.nvidia({}, self.config["inference"], self.root)
        self.assertEqual(result["http_status"], 503)
        self.assertTrue(result["response_truncated"])
        self.assertIn("[REDACTED] unavailable", result["raw_response"])
        self.assertNotIn("synthetic-key", json.dumps(result))
        self.assertEqual(result["response_headers"], {"retry-after": "30"})
        self.assertEqual(opener.return_value.open.call_count, 1)

    def test_zero_live_calls_by_default(self):
        cfg = config.load("nemotron-pilot")
        path = runner.new_run(self.root, cfg)
        with patch("simlab.policies.nvidia") as inference:
            with self.assertRaises(ValueError):
                runner.drive(path, self.root)
            inference.assert_not_called()

    def chain_result(self, model, error=None, status=None, tokens=10):
        return {"provider": "nvidia", "model": model, "usage": {"total_tokens": tokens},
                "error": error, "http_status": status, "seconds": 0.5, "cost_usd": None,
                "response": {"choice": 0, "speech": "", "channel": "public"} if not error else None}

    def test_fallback_chain_uses_backup_after_provider_failure(self):
        inference = dict(self.config["inference"], model="primary", fallback_models=["backup"], max_attempts=2)
        replies = [self.chain_result("primary", "http_error", 503), self.chain_result("backup")]
        with patch("simlab.policies.nvidia", side_effect=replies) as call:
            result = policies.attempt_chain({"model": "primary"}, inference, self.root)
        self.assertEqual([c.args[0]["model"] for c in call.call_args_list], ["primary", "backup"])
        self.assertEqual(result["models_tried"], ["primary", "backup"])
        self.assertEqual(result["attempt_count"], 2)
        self.assertIsNone(result["error"])
        self.assertTrue(result["used_fallback_model"])
        self.assertEqual(result["usage"]["total_tokens"], 20)
        self.assertEqual(result["attempts"][0]["http_status"], 503)

    def test_fallback_chain_is_bounded(self):
        inference = dict(self.config["inference"], model="primary", fallback_models=["backup"], max_attempts=3)
        failure = self.chain_result("primary", "http_error", 503)
        with patch("simlab.policies.nvidia", return_value=failure) as call:
            exhausted = policies.attempt_chain({}, inference, self.root)
            self.assertEqual(call.call_count, 3)
            self.assertEqual(exhausted["attempt_count"], 3)
            self.assertEqual(exhausted["error"], "http_error")
            call.reset_mock()
            # The remaining call budget lowers the ceiling; it can never raise it.
            capped = policies.attempt_chain({}, inference, self.root, 1)
            self.assertEqual(call.call_count, 1)
            self.assertEqual(capped["attempt_budget"], 1)

    def test_chain_stops_on_credentials_and_skips_missing_models(self):
        inference = dict(self.config["inference"], model="primary", fallback_models=["backup"], max_attempts=4)
        with patch("simlab.policies.nvidia", return_value=self.chain_result("primary", "http_error", 401)) as call:
            policies.attempt_chain({}, inference, self.root)
            self.assertEqual(call.call_count, 1)
        missing = [self.chain_result("primary", "http_error", 404), self.chain_result("backup", "http_error", 503),
                   self.chain_result("backup", "http_error", 503)]
        with patch("simlab.policies.nvidia", side_effect=missing) as call:
            result = policies.attempt_chain({}, inference, self.root)
        # A 404 model is not tried again in the same decision; the bound still holds.
        self.assertEqual(result["models_tried"], ["primary", "backup", "backup"])
        self.assertEqual(call.call_count, 3)

    def test_live_decision_counts_every_attempt_and_records_the_model(self):
        cfg = config.load("nemotron-pilot", ['inference.model="primary"', 'inference.fallback_models=["backup"]',
                                             "inference.max_attempts=2"])
        path = runner.new_run(self.root, cfg)
        replies = [self.chain_result("primary", "http_error", 503), self.chain_result("backup")]
        with patch.dict("os.environ", NVIDIA_API_KEY="synthetic-key"), patch("simlab.policies.preflight"), \
                patch("simlab.policies.nvidia", side_effect=replies):
            result = runner.drive(path, self.root, live=True, max_steps=1)
        metrics = result["metrics"]
        self.assertEqual(metrics["usage"]["calls"], 2)
        self.assertEqual(metrics["segment_fallbacks"], 0)
        self.assertEqual(metrics["decisions_by_model"], {"backup": 1})
        self.assertEqual(metrics["attempts_by_model"], {"primary": 1, "backup": 1})
        self.assertTrue(runner.replay(path)["verified"])

    def test_exhausted_chain_still_yields_a_labeled_wait(self):
        cfg = config.load("nemotron-pilot", ['inference.model="primary"', 'inference.fallback_models=["backup"]',
                                             "inference.max_attempts=2"])
        path = runner.new_run(self.root, cfg)
        with patch.dict("os.environ", NVIDIA_API_KEY="synthetic-key"), patch("simlab.policies.preflight"), \
                patch("simlab.policies.nvidia", return_value=self.chain_result("primary", "http_error", 503)):
            result = runner.drive(path, self.root, live=True, max_steps=1)
        rows = [r for r in storage.journal(path) if r["kind"] == "commit" and r["operation"]["kind"] == "decision"]
        self.assertEqual(rows[-1]["operation"]["fallback"], "http_error")
        self.assertEqual(rows[-1]["operation"]["proposal"]["action"]["kind"], "wait")
        self.assertIsNone(rows[-1]["operation"]["model"])
        self.assertEqual(result["metrics"]["usage"]["calls"], 2)
        self.assertEqual(result["metrics"]["segment_fallbacks"], 1)

    def test_recorded_controller(self):
        cfg = copy.deepcopy(self.config)
        for actor in cfg["actors"]:
            actor["policy"] = "recorded"
        trace = self.root / "recorded.json"
        storage.atomic(trace, {})
        cfg["recorded_decisions"] = str(trace)
        path, result = self.run_new(cfg, steps=1)
        self.assertEqual(result["metrics"]["usage"]["fallbacks"], 1)
        self.assertTrue(runner.replay(path)["verified"])


if __name__ == "__main__":
    unittest.main()
