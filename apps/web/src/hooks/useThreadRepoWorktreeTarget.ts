import { useAtomSet, useAtomValue } from "@effect/atom-react";
import {
  childRepositoryTargets,
  resolveSelectedRepoWorktree,
} from "@t3tools/client-runtime/state/threads";
import type { ScopedThreadRef, ThreadRepoWorktree } from "@t3tools/contracts";
import { Atom } from "effect/reactivity";

import { useDiffPanelStore } from "../diffPanelStore";
import { useEnvironmentQuery } from "../state/query";
import { useQuietThreadShell } from "../state/entities";
import { environmentThreadDetails } from "../state/threads";
import { vcsEnvironment } from "../state/vcs";

const NO_REPO_WORKTREES = Atom.make<ReadonlyArray<ThreadRepoWorktree>>([]);
const EMPTY_ITEMS = Atom.make<readonly never[]>([]);
const NO_SELECTION = Atom.make<string | null | undefined>(undefined);

/**
 * The repository worktree a thread's Changes and Git actions use, chosen per
 * thread. Null means the thread's own workspace.
 */
export function useThreadRepoWorktreeTarget(input: {
  readonly threadRef: ScopedThreadRef | null;
  /** The thread's own workspace: its worktree or the project folder. */
  readonly workspaceCwd: string | null;
}) {
  const thread = useQuietThreadShell(input.threadRef);
  const attached = useAtomValue(
    input.threadRef === null
      ? NO_REPO_WORKTREES
      : environmentThreadDetails.repoWorktreesAtom(input.threadRef),
  );
  const selectionAtom =
    input.threadRef === null
      ? NO_SELECTION
      : environmentThreadDetails.repoWorktreeSelectionAtom(input.threadRef);
  const selection = useAtomValue(selectionAtom);
  const setSelection = useAtomSet(selectionAtom);
  // Shared with the thread's own status query, so this costs nothing extra.
  const workspaceStatus = useEnvironmentQuery(
    input.threadRef !== null && input.workspaceCwd !== null
      ? vcsEnvironment.status({
          environmentId: input.threadRef.environmentId,
          input: { cwd: input.workspaceCwd },
        })
      : null,
  );
  const children = workspaceStatus.data?.childRepositories;
  const items = useAtomValue(
    input.threadRef && children?.length
      ? environmentThreadDetails.quietVisibleTurnItemsAtom(input.threadRef)
      : EMPTY_ITEMS,
  );
  const discovered = childRepositoryTargets(input.workspaceCwd, children, items).filter(
    (child) => !attached.some((entry) => entry.repository === child.repository),
  );
  const repoWorktrees = [...attached, ...discovered];
  const repoWorktree = resolveSelectedRepoWorktree({
    repoWorktrees,
    pullRequests: thread?.pullRequests ?? [],
    selection,
    workspaceIsRepository: workspaceStatus.data?.isRepo ?? true,
  });
  const select = (worktreePath: string | null) => {
    if (worktreePath === (repoWorktree?.worktreePath ?? null)) return;
    if (input.threadRef !== null) useDiffPanelStore.getState().clearGitComparison(input.threadRef);
    setSelection(worktreePath);
  };
  return { repoWorktrees, repoWorktree, select };
}
