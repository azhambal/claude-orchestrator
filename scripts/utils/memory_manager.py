#!/usr/bin/env python3
"""
Simple memory manager for Claude Orchestrator
Manages core/working/archival memory layers (file-based)

Usage:
  memory_manager.py store-core <key> [data]
  memory_manager.py store-working <key> [data]
  memory_manager.py store-archival <key> [data]
  memory_manager.py get <key>
  memory_manager.py evict [max_age_seconds]
"""

import json
import time
from pathlib import Path
from typing import Optional, Dict, Any
import sys

class MemoryManager:
    def __init__(self, memory_dir: str = ".claude/memory"):
        self.memory_dir = Path(memory_dir)
        self.core_dir = self.memory_dir / "core"
        self.working_dir = self.memory_dir / "working"
        self.archival_dir = self.memory_dir / "archival"

        # Ensure dirs exist
        for d in [self.core_dir, self.working_dir, self.archival_dir]:
            d.mkdir(parents=True, exist_ok=True)

    def store_core(self, key: str, data: Any):
        """Store in core memory (hot, current session)"""
        file = self.core_dir / f"{key}.json"
        with open(file, 'w') as f:
            json.dump({
                "key": key,
                "data": data,
                "stored_at": time.time()
            }, f, indent=2)

    def store_working(self, key: str, data: Any):
        """Store in working memory (recent sessions)"""
        file = self.working_dir / f"{key}.json"
        with open(file, 'w') as f:
            json.dump({
                "key": key,
                "data": data,
                "stored_at": time.time()
            }, f, indent=2)

    def store_archival(self, key: str, data: Any):
        """Store in archival memory (long-term)"""
        file = self.archival_dir / f"{key}.json"
        with open(file, 'w') as f:
            json.dump({
                "key": key,
                "data": data,
                "stored_at": time.time()
            }, f, indent=2)

    def get(self, key: str) -> Optional[Any]:
        """Get from memory (checks core → working → archival)"""
        # Try core first
        file = self.core_dir / f"{key}.json"
        if file.exists():
            with open(file, 'r') as f:
                return json.load(f).get("data")

        # Try working
        file = self.working_dir / f"{key}.json"
        if file.exists():
            with open(file, 'r') as f:
                return json.load(f).get("data")

        # Try archival
        file = self.archival_dir / f"{key}.json"
        if file.exists():
            with open(file, 'r') as f:
                return json.load(f).get("data")

        return None

    def evict_core(self, max_age_seconds: int = 3600):
        """Evict old core memory to working"""
        now = time.time()
        evicted = 0
        for file in self.core_dir.glob("*.json"):
            try:
                with open(file, 'r') as f:
                    data = json.load(f)
                    if now - data.get("stored_at", now) > max_age_seconds:
                        # Move to working
                        key = data.get("key")
                        self.store_working(key, data.get("data"))
                        file.unlink()
                        evicted += 1
            except:
                pass
        return evicted

def main():
    if len(sys.argv) < 2:
        print("Usage: memory_manager.py <store-core|store-working|store-archival|get|evict> <key> [data]")
        sys.exit(1)

    mm = MemoryManager()
    command = sys.argv[1]

    if command in ["store-core", "store-working", "store-archival"]:
        if len(sys.argv) < 3:
            print(f"Usage: memory_manager.py {command} <key> [data]")
            sys.exit(1)
        key = sys.argv[2]
        data_str = sys.argv[3] if len(sys.argv) > 3 else sys.stdin.read()
        try:
            data = json.loads(data_str)
        except:
            data = data_str

        if command == "store-core":
            mm.store_core(key, data)
        elif command == "store-working":
            mm.store_working(key, data)
        else:
            mm.store_archival(key, data)

        print(f"Stored {key} in {command.replace('store-', '')}")

    elif command == "get":
        if len(sys.argv) < 3:
            print("Usage: memory_manager.py get <key>")
            sys.exit(1)
        key = sys.argv[2]
        data = mm.get(key)
        if data:
            print(json.dumps(data, indent=2))
        else:
            print(f"Key not found: {key}", file=sys.stderr)
            sys.exit(1)

    elif command == "evict":
        max_age = int(sys.argv[2]) if len(sys.argv) > 2 else 3600
        evicted = mm.evict_core(max_age)
        print(f"Evicted {evicted} entries from core to working")

    else:
        print(f"Unknown command: {command}")
        sys.exit(1)

if __name__ == "__main__":
    main()
