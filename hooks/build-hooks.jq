def dispatch($n): "bash \"${CLAUDE_PLUGIN_ROOT}/.claude/hooks/plugin-dispatch.sh\" \($n)";
{
  description: "laravel-workflow hooks (plugin install). Generated from .claude/settings.json by `jq -f hooks/build-hooks.jq .claude/settings.json > hooks/hooks.json`; each runs through plugin-dispatch.sh, which steps aside when the project has its own install.",
  hooks: (
    .hooks
    | with_entries(.value |= map(.hooks |= map(
        .command |= (capture("/\\.claude/hooks/(?<n>[a-z-]+)\\.sh$").n as $n | dispatch($n))
      )))
    | .SubagentStart |= map(.matcher = "(^|:)(laravel|blade)-")
    | .PreToolUse = (
        [{matcher: "Read", hooks: [{type: "command", command: dispatch("guard-read"), timeout: 10}]}]
        + (.PreToolUse | map(if .matcher == "Bash" then .hooks += [{type: "command", command: dispatch("allow-helpers"), timeout: 10}] else . end))
        + [{matcher: "mcp__laravel-boost__.*", hooks: [{type: "command", command: dispatch("allow-helpers"), timeout: 10}]}]
      )
  )
}
