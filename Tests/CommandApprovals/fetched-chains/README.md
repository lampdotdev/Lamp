Runs each chain of commands through `Fetched.step` in order, with the real decision model, and counts the cards.

    swiftc -O -o chains stub.swift ../../../Sources/Lamp/Fetched.swift main.swift
    OPENROUTER_API_KEY=… RUNS=5 ./chains
