Settings → Repository → Deploy tokens → Add token

GITLAB_API_TOKEN

What it is: Another custom variable you named. It’s meant to hold an access token for GitLab’s API.

Why you need it (in your repo specifically): Your publish_generic.sh does:

List packages via GET /projects/:id/packages

Delete matching packages so you can “overwrite” a stable latest version
It authenticates those delete/list calls with PRIVATE-TOKEN: ${GITLAB_API_TOKEN} (your script literally requires it with req GITLAB_API_TOKEN).

GitLab’s generic packages docs say you can authenticate to the package registry using:

a personal access token with scope api,

a project access token with scope api (and at least Developer),

a CI/CD job token,

or a deploy token with package registry scopes.

Where to create it (recommended options):

Option A (recommended): Project Access Token

This keeps scope limited to the project.

Project → Settings → Access tokens

Add new token

Choose:

Role: I’d pick Maintainer (because you’re deleting packages; deletion requires sufficient permission)

Scopes: api

Create and copy the token (you only see it once).

Then store it as a CI/CD variable:

Key: GITLAB_API_TOKEN

Value: (the token)

Masked + Protected (recommended)

Option B: Personal Access Token (PAT)

Works too, but it’s broader (tied to your user). PATs are used in place of a password for API auth.
If you do this, still give it only what you need (typically api).
