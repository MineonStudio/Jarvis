# Git 开发与发布流程

Jarvis 使用 `main` 加短期功能分支。`main` 保存已验收的集成代码，版本标签标记正式发布点；本地开发版不是 Git 分支，不需要长期 `dev` 分支。

用户明确授权提交并合并后，代理优先使用 `python3 script/submit_pr.py --title ... --body-file ...` 连续完成推送、PR、等待检查、Squash 合并、同步本地 `main` 和清理本次分支，无需逐步再次确认。参数及数据保护边界见[自动提交、合并与清理](git-automation.md)。

## 日常开发

1. 检查 `git status`，妥善保存现有修改；执行 `git fetch origin --prune`。
2. 从最新主干创建功能分支，例如 `git switch -c codex/example-task origin/main`。工作区已有修改时先保存或提交到所属功能分支，不强制切换覆盖文件。
3. 按逻辑提交改动，使用清晰的提交说明，例如 `fix: ...`、`refactor: ...` 或 `docs: ...`。一个任务一个 PR，无关工作分开提交。
4. 运行适用的检查，并运行 `./script/build_and_run.sh --verify`，在本机验收开发版。Swift 工具需要完整 Xcode，可设置 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。
5. 使用 `git push -u origin codex/example-task` 推送当前功能分支，向 `main` 创建 PR，填写仓库 PR 模板。
6. 等待远程 `quality` 检查通过，检查 PR 差异并完成本地验收。主干前进时更新功能分支并重新验证；共享分支优先合并 `origin/main`，不要擅自改写他人提交。
7. 由维护者决定合并，使用 Squash。代理创建 PR 后应报告链接和检查状态，未经明确要求不执行合并或发布。
8. GitHub 自动删除已合并的远程功能分支。确认工作区干净后切换到本地 `main`，执行 `git pull --ff-only origin main`。确认提交已通过 PR 合入后，再删除本地功能分支；Squash 后 Git 可能无法通过祖先关系识别已合入的提交，应先核对 PR 与合并结果。

## 仓库规则

GitHub Settings 中使用 `Protect main` 分支 ruleset：

- 状态为 Active，只匹配 `refs/heads/main`，绕过列表为空。
- 要求通过 PR 合并；审批人数为 0，避免单人维护时要求作者无法提供的自我批准。维护者仍需检查 PR 并决定合并。
- 必需检查为 GitHub Actions 提供的 `quality`；功能分支必须与主干保持同步。
- 要求解决审查讨论，阻止强制推送和删除 `main`。
- 允许 Squash 合并，不启用 Restrict updates；该选项会额外限制分支更新，不是 PR 要求的替代项。

仓库 General 设置只启用 Squash 合并，并自动删除已合并的功能分支。规则可能被管理员后续修改，远程实际设置为准；修改规则后需重新读取验证。

本地使用仓库级 `push.default=simple`，不要设置 `remote.origin.push=refs/heads/main:refs/heads/main`。新分支首次推送始终显式指定分支和 `-u`。

## 本地验证与 CI

CI 位于 `.github/workflows/quality.yml`，覆盖 SwiftFormat、SwiftLint、Release 构建、Swift 测试、Rust 测试和应用打包检查。必须分别报告本地验证和远程 CI 的结果，跳过的测试需说明原因。

本地验收覆盖本机窗口、权限和开发版行为；CI 通过不能替代本地验收，本地测试通过也不能替代远程必需检查。文档类修改同样遵守 `AGENTS.md` 的开发版构建启动约定。

## 发布

PR 合并不自动发布新版本。需要发版时：

1. 确认 `main` 与远程同步、工作区干净，当前提交的 `quality` 已通过。
2. 通过 PR 完成版本及构建号调整，记录最终主干提交 SHA。
3. 在该提交创建新的 `v<version>` 标签，已发布标签不移动。
4. 从该提交按 `docs/update-release.md` 构建、签名和验收发布资产，再创建对应 GitHub Release。
5. 发布后记录版本、标签、提交及 CI 链接。若需修复，创建修复分支和新 PR，再发布新的补丁版本。

现有发布脚本负责产物构建与签名；发布前的干净工作区、提交和 CI 状态需按此流程核对，不假定脚本已强制执行这些条件。
