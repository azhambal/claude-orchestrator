#!/usr/bin/env python3
"""
Simple context window tracker for Claude Orchestrator
Estimates token usage and warns on overflow

Usage:
  context_tracker.py log <agent> [text]
  context_tracker.py status
"""

import json
import time
from pathlib import Path
import sys

class ContextTracker:
    def __init__(self, max_tokens=200000):
        self.max_tokens = max_tokens
        self.log_file = Path(".claude/logs/context_usage.jsonl")
        self.thresholds = {
            'green': 0.50,   # < 50%
            'yellow': 0.70,  # 50-70%
            'orange': 0.85,  # 70-85%
            'red': 0.95      # > 85%
        }

    def estimate_tokens(self, text: str) -> int:
        """Rough estimate: ~4 chars per token"""
        return len(text) // 4

    def log_usage(self, agent: str, prompt: str, component: str = "prompt"):
        """Log token usage for a component"""
        tokens = self.estimate_tokens(prompt)

        entry = {
            "timestamp": time.time(),
            "agent": agent,
            "component": component,
            "tokens": tokens,
            "estimated_total": tokens  # Simplified
        }

        self.log_file.parent.mkdir(parents=True, exist_ok=True)
        with open(self.log_file, 'a') as f:
            f.write(json.dumps(entry) + '\n')

        # Check threshold
        usage_percent = tokens / self.max_tokens
        status = self._get_status(usage_percent)

        if status in ['orange', 'red']:
            print(f"[WARNING] Context usage: {usage_percent*100:.1f}% ({status})", file=sys.stderr)
            print(f"  Tokens: {tokens} / {self.max_tokens}", file=sys.stderr)

        return tokens

    def get_total_usage(self) -> dict:
        """Get total usage from logs"""
        if not self.log_file.exists():
            return {"total_tokens": 0, "status": "green", "max_tokens": self.max_tokens, "usage_percent": 0}

        total = 0
        count = 0
        with open(self.log_file, 'r') as f:
            for line in f:
                try:
                    entry = json.loads(line)
                    total += entry.get("tokens", 0)
                    count += 1
                except:
                    pass

        usage_percent = total / self.max_tokens
        status = self._get_status(usage_percent)

        return {
            "total_tokens": total,
            "max_tokens": self.max_tokens,
            "usage_percent": usage_percent * 100,
            "status": status,
            "entries": count
        }

    def _get_status(self, usage_percent: float) -> str:
        if usage_percent < self.thresholds['green']:
            return 'green'
        elif usage_percent < self.thresholds['yellow']:
            return 'yellow'
        elif usage_percent < self.thresholds['orange']:
            return 'orange'
        else:
            return 'red'

def main():
    if len(sys.argv) < 2:
        print("Usage: context_tracker.py <log|status> [agent] [text]")
        sys.exit(1)

    tracker = ContextTracker()
    command = sys.argv[1]

    if command == "log":
        if len(sys.argv) < 3:
            print("Usage: context_tracker.py log <agent> [text]")
            sys.exit(1)
        agent = sys.argv[2]
        text = sys.argv[3] if len(sys.argv) > 3 else sys.stdin.read()
        tokens = tracker.log_usage(agent, text)
        print(f"Logged {tokens} tokens for {agent}")

    elif command == "status":
        usage = tracker.get_total_usage()
        print(json.dumps(usage, indent=2))

    else:
        print(f"Unknown command: {command}")
        sys.exit(1)

if __name__ == "__main__":
    main()
