# Vercel Deployment Recovery

The repository can continue to receive and validate source changes while Vercel is temporarily rate-limited. A Vercel deployment failure caused by the account/project deployment quota does not alter the source repository or Supabase database.

## Recovery options

1. **Wait for the rolling deployment limit to clear.** This is the least invasive option. Keep GitHub as the source of truth and deploy the validated `main` commit after the limit resets.
2. **Reduce unnecessary deployments.** Configure Vercel Ignored Build Step so documentation-only or otherwise irrelevant commits do not start builds. The command must return 0 only when the build should be skipped and 1 when the application must build.
3. **Use a controlled CI deployment.** Run typecheck, lint, contract tests and the production build in GitHub Actions, then deploy the resulting Vercel build output with `vercel deploy --prebuilt --prod`. Deployment credentials must be stored as GitHub secrets and never committed.
4. **Validate a preview first, then promote it.** Once a preview deployment is successfully built, validate it and promote the exact deployment to production instead of rebuilding. This reduces another build during promotion.
5. **Use Vercel Pro if the deployment quota is the bottleneck.** This changes the account-level deployment capacity and is preferable to repeatedly retrying a quota-blocked Hobby deployment.
6. **Keep source changes on GitHub while blocked.** A push to `main` remains a normal source-control operation. With Git integration enabled, however, the push may create another Vercel deployment attempt and consume deployment quota, so avoid repeated no-op pushes solely to test Vercel while the limit is active.

## Safety rule

Do not treat a Vercel rate-limit failure as an application build failure. The deployment gate remains incomplete until a successful build/deployment is produced and the deployed application is browser-verified. Do not alter Supabase production state merely to work around a Vercel deployment quota.
