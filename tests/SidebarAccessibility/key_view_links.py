"""SidebarView is not compiled by the key-view suites: every place it links its
chain must pass the window owner's exit, bypass the chain while the sidebar is
not presented and skip the Space pages it isn't showing (the linker's behaviour for
each is run in SidebarAccessibilityTests)."""


def sidebar_link_calls(sidebar):
    calls, start = [], sidebar.find("SidebarAccessibility.link(")
    while start != -1:
        line = sidebar[sidebar.rfind("\n", 0, start) + 1:start]
        depth, end = 0, sidebar.index("(", start)
        if "//" not in line:
            for end in range(end, len(sidebar)):
                depth += {"(": 1, ")": -1}.get(sidebar[end], 0)
                if depth == 0:
                    break
            assert depth == 0, "a SidebarAccessibility.link call in SidebarView never closes"
            calls.append(" ".join(sidebar[start:end + 1].split()))
        start = sidebar.find("SidebarAccessibility.link(", end + 1)
    return calls


def assert_sidebar_links(sidebar):
    calls = sidebar_link_calls(sidebar)
    assert calls, "SidebarView no longer links its key-view chain through SidebarAccessibility.link"
    for call in calls:
        for argument in ("within: self", "exit: keyViewExit", "bypassed: !isPresented",
                         "skipping: { ($0 as? SidebarPageStripView)?.passesThrough == true }"):
            assert argument in call, f"SidebarView links its chain without {argument}: {call}"
