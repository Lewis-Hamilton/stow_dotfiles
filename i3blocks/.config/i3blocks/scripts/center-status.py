#!/usr/bin/python3
"""Keep the clock/notifications centered ahead of i3blocks' right-hand stats."""

import functools
import json
import itertools
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

import gi

gi.require_version("Pango", "1.0")
gi.require_version("PangoCairo", "1.0")
from gi.repository import Pango, PangoCairo


def ipc(message, *args):
    return json.loads(subprocess.check_output(
        ["i3-msg", "-t", message, *args], text=True, timeout=2))


class CenteredStatus:
    def __init__(self):
        bar = ipc("get_bar_config", "bar-0")
        resources = subprocess.check_output(["xrdb", "-query"], text=True)
        self.dpi = next((float(line.split(":", 1)[1])
                         for line in resources.splitlines()
                         if line.startswith("Xft.dpi:")), 96)
        context = PangoCairo.FontMap.get_default().create_context()
        PangoCairo.context_set_resolution(context, self.dpi)
        self.layout = Pango.Layout.new(context)
        self.layout.set_font_description(Pango.FontDescription.from_string(
            bar["font"].removeprefix("pango:")))
        self.screen_width = 0
        self.checked_at = 0
        # i3bar reserves four logical pixels at the right edge.
        self.edge_padding = round(4 * self.dpi / 96)

    @functools.lru_cache(maxsize=512)
    def text_width(self, text, markup=False):
        self.layout.set_attributes(None)
        if markup:
            self.layout.set_markup(text, -1)
        else:
            self.layout.set_text(text, -1)
        return self.layout.get_pixel_size()[0]

    def block_width(self, block):
        text = block.get("full_text", "")
        if not text:
            return 0
        width = self.text_width(text, block.get("markup") == "pango")
        if block.get("border"):
            width += round((block.get("border_left", 1)
                            + block.get("border_right", 1)) * self.dpi / 96)
        minimum = block.get("min_width", 0)
        if isinstance(minimum, str):
            minimum = self.text_width(minimum)
        return max(width, minimum)

    def group_width(self, blocks):
        return sum(self.block_width(block)
                   + (block.get("separator_block_width", 9)
                      if index < len(blocks) - 1 and block.get("full_text") else 0)
                   for index, block in enumerate(blocks))

    def center(self, blocks):
        now = time.monotonic()
        if now - self.checked_at > 2:
            active = [output for output in ipc("get_outputs") if output["active"]]
            if active:
                # The laptop and dock profiles each enable a single output.
                primary = next((o for o in active if o.get("primary")), active[0])
                self.screen_width = primary["rect"]["width"]
            self.checked_at = now
        index = next((i for i, block in enumerate(blocks)
                      if block.get("name") == "separator_section"), None)
        if index is None or not self.screen_width:
            return blocks
        center, right = blocks[:index], blocks[index + 1:]
        if center:
            center[-1]["separator_block_width"] = 0
        gap = round(self.screen_width / 2 - self.group_width(center) / 2
                    - self.group_width(right) - self.edge_padding)
        # On narrow displays, prioritize keeping all status blocks visible.
        spacer = dict(blocks[index], separator_block_width=0,
                      min_width=max(0, gap),
                      full_text=" " if gap >= self.text_width(" ") else "")
        return [*center, spacer, *right]


def main():
    status = CenteredStatus()
    env = dict(os.environ, SCRIPT_DIR=str(Path(__file__).resolve().parent))
    # Inherit stdin directly: notification/tray click events reach i3blocks.
    child = subprocess.Popen(
        ["i3blocks", "-c", str(Path.home() / ".config/i3blocks/config")],
        env=env, stdin=sys.stdin, stdout=subprocess.PIPE, text=True)
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    try:
        print(child.stdout.readline().rstrip("\n"), flush=True)
        opening = child.stdout.readline()
        print("[", flush=True)
        for line in itertools.chain([opening[1:]], child.stdout):
            if not line.strip():
                continue
            payload = line.lstrip(",").strip()
            if payload.startswith("[") and payload != "[":
                blocks = json.loads(payload)
                line = ("," if line.startswith(",") else "") + json.dumps(status.center(blocks))
            print(line.rstrip("\n"), flush=True)
    finally:
        child.terminate()
        child.wait(timeout=3)


if __name__ == "__main__":
    try:
        main()
    except BrokenPipeError:
        pass
