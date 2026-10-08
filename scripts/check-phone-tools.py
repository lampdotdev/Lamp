#!/usr/bin/env python3
"""Run the phone prerequisite checks without requiring full Xcode or XCTest.

Compile the actual detector, process runners and simulator selection from Lamp. The inputs to Apple's
commands are fixtures; the process-inheritance check runs real child processes. No sign-in is needed.
"""
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
sources = root / "Sources/Lamp"
store = (sources / "Store.swift").read_text()
family = store[store.index("enum DeviceFamily:"):store.index("\n}\n", store.index("enum DeviceFamily:")) + 3]
simulator = (sources / "Simulator.swift").read_text()
simulator = simulator[:simulator.index("    /// Boots the iPhone")] + "}\n"
agent = (sources / "Agent.swift").read_text()
shell = agent[agent.index("enum Shell {"):agent.index("\n///", agent.index("enum Shell {"))]
checks = (root / "Tests/PhoneToolsChecks.swift").read_text()
names = re.findall(r"    func (test\w+)\(", checks)
runner = "\n@main struct RunChecks {\n @MainActor static func main() async throws {\n let checks = PhoneToolsChecks()\n"
for name in names:
    declaration = checks[checks.index("func " + name):].split("{", 1)[0]
    prefix = ("try " if "throws" in declaration else "") + ("await " if "async" in declaration else "")
    runner += f' {prefix}checks.{name}()\n print("PASS {name}")\n'
runner += f' print("{len(names)} phone prerequisite checks passed")\n }}\n}}\n'
with tempfile.TemporaryDirectory(prefix="lamp-phone-checks-") as folder:
    main = Path(folder) / "Checks.swift"
    main.write_text("\n".join([family, (sources / "Subprocess.swift").read_text(), shell,
                               simulator, (sources / "PhoneTools.swift").read_text(), checks, runner]))
    executable = Path(folder) / "checks"
    subprocess.run(["/usr/bin/xcrun", "swiftc", "-parse-as-library", str(main), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
