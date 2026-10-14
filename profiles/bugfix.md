---
required-skills:
  - diagnosing-bugs
  - tdd
permitted-skills:
  - codebase-design
access: full
---

Reproduce the defect with `/diagnosing-bugs` before fixing it. A reproducing
signal is the prerequisite to any patch. Use `/tdd` to turn that signal into a
regression test and drive the repair from red to green. Use `/codebase-design`
if the repair needs a deeper seam. Finish with the reproduction resolved, the
feedback loops passing, and evidence for every acceptance criterion.
