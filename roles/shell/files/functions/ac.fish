function ac --description "Stage all changes and commit with an AI-generated Conventional Commit message"
    if not command -q claude
        echo "claude CLI not found. Install it from https://claude.com/claude-code."
        return 1
    end

    if not git rev-parse --is-inside-work-tree >/dev/null 2>&1
        echo "Not a git repository."
        return 1
    end

    git add -A

    # Checks ALL staged changes, so we still bail correctly even when the
    # noisy files excluded below are the only thing that changed.
    if git diff --cached --quiet
        echo "Nothing to commit."
        return 1
    end

    # --- Large-diff fix 1: hide noisy/generated files from the diff we send to
    # the LLM. These pathspecs ONLY filter what the model sees — every staged
    # file is still committed. Add your own (e.g. ':!*.svg', ':!data/*') as needed.
    set -l exclude \
        ':!*.lock' \
        ':!*-lock.json' \
        ':!*-lock.yaml' \
        ':!pnpm-lock.yaml' \
        ':!Cargo.lock' \
        ':!poetry.lock' \
        ':!uv.lock' \
        ':!*.min.js' ':!*.min.css' ':!*.map' \
        ':!dist/*' ':!build/*' \
        ':!*.snap'

    # --- Large-diff fix 2: cap the diff size so a huge change can't blow up the
    # prompt. string collect keeps the truncated output as one string (so the
    # emptiness test and the pipe below behave correctly).
    set -l max_bytes 100000
    set -l diff (git diff --cached -- . $exclude | head -c $max_bytes | string collect)

    # Fallback: if the excludes stripped everything (e.g. only a lockfile
    # changed), send the file-level summary so the model still has context.
    if test -z "$diff"
        set diff (git diff --cached --stat | head -c $max_bytes | string collect)
    end

    echo "Generating commit message…"

    set -l msg (printf '%s\n' $diff | claude -p --model haiku "Write a single git commit message for the following staged diff, strictly following the Conventional Commits 1.0.0 spec.

Rules:
- Format: <type>[optional scope]: <description>, then an optional body after a blank line.
- type is one of: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert.
- Use a scope in parentheses when it clarifies the affected area.
- Description: imperative mood, lower case, no trailing period, max 72 chars.
- Add a concise body only if the change needs explanation; wrap lines at ~72 chars.
- Split the body into short paragraphs separated by a blank line — one idea per paragraph — to aid readability.
- Use '!' after the type/scope and/or a 'BREAKING CHANGE:' footer for breaking changes.
- Separate the subject and body with a real blank line (an actual newline character, not the two characters backslash-n).
- Output ONLY the raw commit message. No backticks, no quotes, no preamble." | string trim | string collect)

    if test -z "$msg"
        echo "Failed to generate a commit message."
        return 1
    end

    echo
    echo "$msg"
    echo
    if not read -l -P "Commit? [Y/n/e(dit)] " answer
        echo "Aborted. Changes remain staged."
        return 1
    end

    switch $answer
        case '' Y y
            git commit -m "$msg"
        case E e
            git commit -e -m "$msg"
        case '*'
            echo "Aborted. Changes remain staged."
    end
end
