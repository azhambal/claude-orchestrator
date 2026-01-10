#!/usr/bin/env python3
"""
Simple file-based cache for Claude Orchestrator
Reduces redundant file reads by agents

Usage:
  simple_cache.py get <key>
  simple_cache.py set <key> <value> [ttl]
  simple_cache.py invalidate [pattern]
"""

import json
import hashlib
import time
from pathlib import Path
from typing import Optional, Dict, Any
import sys

class SimpleCache:
    def __init__(self, cache_dir: str = ".claude/cache"):
        self.cache_dir = Path(cache_dir)
        self.hot_dir = self.cache_dir / "hot"
        self.warm_dir = self.cache_dir / "warm"
        self.metadata_dir = self.cache_dir / "metadata"

        # Load config
        config_file = self.cache_dir / "config.json"
        self.config = json.load(open(config_file)) if config_file.exists() else {}
        self.enabled = self.config.get("enabled", True)
        self.default_ttl = self.config.get("default_ttl", 3600)

    def get(self, key: str) -> Optional[str]:
        """Get cached value"""
        if not self.enabled:
            return None

        # Try hot cache first
        hot_file = self.hot_dir / f"{self._hash(key)}.cache"
        if hot_file.exists():
            try:
                data = json.load(open(hot_file))
                if self._is_valid(data):
                    return data["value"]
            except:
                pass

        # Try warm cache
        warm_file = self.warm_dir / f"{self._hash(key)}.cache"
        if warm_file.exists():
            try:
                data = json.load(open(warm_file))
                if self._is_valid(data):
                    return data["value"]
            except:
                pass

        return None

    def set(self, key: str, value: str, ttl: Optional[int] = None):
        """Cache a value"""
        if not self.enabled:
            return

        ttl = ttl or self.default_ttl
        cache_entry = {
            "value": value,
            "created_at": time.time(),
            "expires_at": time.time() + ttl if ttl else None
        }

        # Always save to warm (persistent)
        warm_file = self.warm_dir / f"{self._hash(key)}.cache"
        warm_file.parent.mkdir(parents=True, exist_ok=True)
        with open(warm_file, 'w') as f:
            json.dump(cache_entry, f)

    def invalidate(self, pattern: str = None):
        """Invalidate cache entries"""
        if pattern:
            # Invalidate matching files (simplified - just clear all for now)
            for cache_file in self.warm_dir.glob("*.cache"):
                cache_file.unlink()
        else:
            # Clear all
            for cache_file in self.warm_dir.glob("*.cache"):
                cache_file.unlink()
            for cache_file in self.hot_dir.glob("*.cache"):
                cache_file.unlink()

    def _hash(self, key: str) -> str:
        """Hash key to filename"""
        return hashlib.md5(key.encode()).hexdigest()

    def _is_valid(self, cache_entry: Dict) -> bool:
        """Check if cache entry is still valid"""
        expires_at = cache_entry.get("expires_at")
        if expires_at and time.time() > expires_at:
            return False
        return True

def main():
    """CLI interface"""
    if len(sys.argv) < 2:
        print("Usage: simple_cache.py <get|set|invalidate> <key> [value] [ttl]")
        sys.exit(1)

    cache = SimpleCache()
    command = sys.argv[1]

    if command == "get":
        if len(sys.argv) < 3:
            print("Usage: simple_cache.py get <key>")
            sys.exit(1)
        key = sys.argv[2]
        value = cache.get(key)
        if value:
            print(value)
        sys.exit(0 if value else 1)

    elif command == "set":
        if len(sys.argv) < 3:
            print("Usage: simple_cache.py set <key> [value] [ttl]")
            sys.exit(1)
        key = sys.argv[2]
        value = sys.argv[3] if len(sys.argv) > 3 else sys.stdin.read()
        ttl = int(sys.argv[4]) if len(sys.argv) > 4 else None
        cache.set(key, value, ttl)
        print(f"Cached: {key}")

    elif command == "invalidate":
        pattern = sys.argv[2] if len(sys.argv) > 2 else None
        cache.invalidate(pattern)
        print("Cache invalidated")

    else:
        print(f"Unknown command: {command}")
        sys.exit(1)

if __name__ == "__main__":
    main()
