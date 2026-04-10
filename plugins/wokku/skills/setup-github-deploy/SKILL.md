---
description: Connect a GitHub repository to a Wokku app for automatic deployment on every push
---

# Setup GitHub Auto-Deploy

Connect a GitHub repo to a Wokku app so pushes to a branch trigger automatic deploys.

## Steps

1. **Identify the app**
   - If user didn't specify, use `wokku_list_apps` and ask which one
   - Use `wokku_get_app` to confirm it exists

2. **Check current deploy method**
   - If the app already has GitHub connected, ask if they want to change it
   - If they just want to update the branch, use `wokku_update_app` with the new `deploy_branch`

3. **Guide through GitHub OAuth connection**
   - GitHub OAuth flow requires the Web UI (Claude Code can't complete OAuth)
   - Tell the user:
     > "GitHub connection requires an OAuth authorization. Please:
     > 1. Go to https://wokku.dev/dashboard/apps/{app_id}
     > 2. Click 'Connect GitHub'
     > 3. Select your repository and branch
     > 4. Click 'Save'"
   - Wait for user confirmation that it's connected

4. **Verify the connection**
   - Use `wokku_get_app` to check that `deploy_branch` is set correctly
   - Confirm with user that a test push will work

5. **Test the auto-deploy**
   - Tell the user to push a small change (like README update)
   - After they push, use `wokku_list_deploys` to check if a new deploy started
   - Use `wokku_get_logs` to stream the build output

## Notes

- Auto-deploys trigger on every push to the connected branch
- Pull request previews are a separate feature (not covered by this skill)
- If the user wants to use git push directly instead of GitHub, use the deploy-new-app skill
