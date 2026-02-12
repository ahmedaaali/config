tofu init -reconfigure \

tofu init \
  -backend-config="address=${TF_ADDRESS}" \
  -backend-config="lock_address=${TF_LOCK_ADDRESS}" \
  -backend-config="unlock_address=${TF_UNLOCK_ADDRESS}" \
  -backend-config="username=${TF_USERNAME}" \
  -backend-config="password=${TOFU_BOT_TOKEN}" \
  -backend-config="lock_method=${TF_LOCK_METHOD}" \
  -backend-config="unlock_method=${TF_UNLOCK_METHOD}" \
  -backend-config="retry_wait_min=${TF_RETRY_WAIT_MIN}"

tofu import 'gitlab_branch_protection.protect_default["gitlab_admin"]' "3:main"
tofu import 'gitlab_branch_protection.protect_default["netbootxyz"]'  "2:main"
tofu import 'gitlab_branch_protection.protect_default["proxmox"]'     "1:main"
tofu import 'gitlab_branch.ahmed["gitlab_admin"]' "3:ahmed"
tofu import 'gitlab_branch.ahmed["netbootxyz"]'  "2:ahmed"
tofu import 'gitlab_branch.ahmed["proxmox"]'     "1:ahmed"
tofu import 'gitlab_user_runner.shared[0]' 1
tofu import 'gitlab_group_membership.members["ahmed_owner"]' '2:2'

tofu import 'gitlab_project_variable.project_variables["PVE_ROOT_PASSWORD|pve/serfer"]' '1:PVE_ROOT_PASSWORD:pve/serfer'

tofu state show 'gitlab_branch_protection.protect_default["gitlab_admin"]' "3:main"
tofu state show 'gitlab_branch_protection.protect_default["netbootxyz"]'  "2:main"
tofu state show 'gitlab_branch_protection.protect_default["proxmox"]'     "1:main"
tofu state show 'gitlab_branch.ahmed["gitlab_admin"]' "3:ahmed"
tofu state show 'gitlab_branch.ahmed["netbootxyz"]'  "2:ahmed"
tofu state show 'gitlab_branch.ahmed["proxmox"]'     "1:ahmed"
tofu state show 'gitlab_user_runner.shared[0]' 1
tofu state show 'gitlab_group_membership.members["ahmed_owner"]'

tofu state rm 'gitlab_group_membership.members["ahmed_owner"]'

tofu force-unlock 78351c39-3f3b-de41-3b79-1d0bd1210b8b 

tofu state mv 'gitlab_branch_protection.protect_main["proxmox"]' 'gitlab_branch_protection.protect_default["proxmox"]'
tofu state mv 'gitlab_branch_protection.protect_main["netbootxyz"]' 'gitlab_branch_protection.protect_default["netbootxyz"]'
tofu state mv 'gitlab_branch_protection.protect_main["gitlab_admin"]' 'gitlab_branch_protection.protect_default["gitlab_admin"]'

tofu plan -out plan.cache
tofu apply plan.cache
rm plan.cache

tofu state show -show-sensitive 'gitlab_project_variable.project_variables["TF_USERNAME"]'

tofu fmt -recursive

tofu output --json runner_tokens
tofu output --json runner_tokens | jq 'with_entries(select(.value != null))'
tofu output --json runner_tokens | jq -r '.proxmox'

9) Add pre-commit so the repo stays clean

Common hooks:

terraform_fmt

tflint

checkov/tfsec

end-of-file-fixer

trailing-whitespace
