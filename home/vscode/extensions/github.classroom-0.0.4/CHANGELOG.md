# Release Notes for GitHub Classroom Visual Studio Code Extension

## 0.0.4 (November 2, 2023)
- Added a note to the README that this extension is not under active development. We still expect the one-click "Open in VS Code" Experience on GitHub Classroom to work, but some features of the extension may not work as expected in the future
- Changed the support link to https://github.com/orgs/community/discussions/categories/github-education

## 0.0.3 (August 19, 2021)
- Fixed a bug that prevented users with a large number of assignments from seeing all of them.

## 0.0.2 (August 12, 2021)

- Added assignment name and due date to the `Assignment` view.
- Fixed a bug that prevented the `Assignment` view from rendering properly in some cases.
- Fixed a bug that prevented already committed changes from being pushed when the directory is otherwise clean.

## 0.0.1 (August 9, 2021)

🚀 GitHub Classroom extension initial preview release 🚀

- Accepted assignments can be explored and opened from the GitHub View or via the `Open Assignment` command.
- When an assignment is opened, details for its tests and collaboration group are accessible from the Explorer View.
- The `Sync Changes` command prompts for a commit message then performs a git fetch, merge, and push for the currently open assignment.
- `Sync Changes` triggers tests to run, with status and results displayed in the `Assignment` view.
- Team members and admins can be invited to join an assignment workspace by inviting individuals from the `Assignment` view.
