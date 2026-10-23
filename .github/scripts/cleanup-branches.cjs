// One-time cleanup for the reviewed integration batch. Never delete a changed head.
module.exports = async ({github, context, core}) => {
  const {owner, repo} = context.repo;
  const {data: repository} = await github.rest.repos.get({owner, repo});
  for (let pull_number = 1; pull_number <= 17; pull_number++) {
    const {data: pr} = await github.rest.pulls.get({owner, repo, pull_number});
    if (!pr.merged || pr.head.repo?.full_name !== `${owner}/${repo}` || pr.head.ref === repository.default_branch) continue;
    try {
      const {data: ref} = await github.rest.git.getRef({owner, repo, ref: `heads/${pr.head.ref}`});
      if (ref.object.sha !== pr.head.sha) {
        core.warning(`Preserving changed branch ${pr.head.ref}`);
        continue;
      }
      await github.rest.git.deleteRef({owner, repo, ref: `heads/${pr.head.ref}`});
      core.info(`Deleted merged branch ${pr.head.ref} (PR #${pull_number})`);
    } catch (error) {
      if (error.status !== 404) throw error;
    }
  }
};
