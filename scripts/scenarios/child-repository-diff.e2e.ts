import { expect } from "e2e";
import * as Effect from "effect/Effect";
import * as FileSystem from "effect/FileSystem";

import { run } from "./shell.ts";
import { runPromise, test, WEB } from "./t3.ts";

test(
  "Changes shows a child checkout before a pull request exists",
  WEB,
  async ({ t3, screen, app }) => {
    const project = await t3.project("workspace");
    await runPromise(
      Effect.gen(function* () {
        const fs = yield* FileSystem.FileSystem;
        const child = project + "/auth";
        yield* fs.makeDirectory(child);
        yield* fs.rename(project + "/.git", child + "/.git");
        yield* fs.rename(project + "/README.md", child + "/README.md");
        yield* run("git", ["checkout", "-b", "feature"], { cwd: child });
        yield* run("git", ["clone", "--local", child, "flx"], { cwd: project });
        yield* fs.writeFileString(project + "/flx/worker.txt", "second checkout\n");
        yield* fs.writeFileString(child + "/README.md", "local edit\n");
      }),
    );
    const thread = await t3.thread({ project, title: "Local changes", messages: ["first"] });
    await t3.open(thread);
    await screen.getByRole("button", "Toggle right panel").tap();
    await screen.getByText("Diff").tap();
    await expect(screen.getByRole("button", "Repository: auth")).toBeVisible();
    await expect(screen.getByRole("button", "Expand README.md")).toBeVisible();
    await app.screenshot("child-changes");
    await screen.getByRole("button", "Repository: auth").tap();
    await screen.getByRole("menuitemradio", "flx").tap();
    await expect(screen.getByRole("button", "Expand worker.txt")).toBeVisible();
  },
);
