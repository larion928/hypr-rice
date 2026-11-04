"""For each id given, lists the members used as id.member that the object with that id never defines."""
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text()
missing = False
for object_id in sys.argv[2:]:
    start = text.index(f"id: {object_id}\n")
    # The object's body: from the brace that opens it to the one that closes it.
    opening = text.rfind("{", 0, start)
    depth, end = 0, opening
    for end in range(opening, len(text)):
        depth += {"{": 1, "}": -1}.get(text[end], 0)
        if depth == 0:
            break
    body = text[opening:end]
    defined = set(re.findall(r"(?:property\s+\w+(?:<\w+>)?|signal|function)\s+(\w+)", body))
    defined |= {"running", "command", "text", "x", "y", "width", "height", "visible", "write"}
    used = set(re.findall(rf"\b{object_id}\.(\w+)", text))
    for name in sorted(used - defined):
        print(f"{object_id}.{name} is used but not defined")
        missing = True
sys.exit(1 if missing else 0)
