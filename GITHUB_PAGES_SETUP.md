# Marxist Library public information site

The dependency-free site in `docs/` is prepared for GitHub Pages. It includes:

- a public landing page;
- the required iOS Privacy Policy page;
- the required App Support page;
- an optional Account & Data / privacy-choices page;
- optional service terms that supplement Apple's standard EULA;
- a responsive shared design, favicon, and 404 page.

## Publish it

1. Commit and push the `docs/` directory to the repository's `main` branch.
2. Open `Tanjiro05-netizen/MarxistAndroidApp` on GitHub.
3. Go to **Settings → Pages**.
4. Under **Build and deployment**, choose **Deploy from a branch**.
5. Select branch **main**, folder **/docs**, then choose **Save**.
6. Wait for GitHub's deployment to finish and verify every URL below without
   being signed into GitHub.

The resulting public URLs are expected to be:

- `https://tanjiro05-netizen.github.io/MarxistAndroidApp/`
- `https://tanjiro05-netizen.github.io/MarxistAndroidApp/privacy.html`
- `https://tanjiro05-netizen.github.io/MarxistAndroidApp/support.html`
- `https://tanjiro05-netizen.github.io/MarxistAndroidApp/account-and-data.html`
- `https://tanjiro05-netizen.github.io/MarxistAndroidApp/terms.html`

No purchased domain, GitHub Actions workflow, package installation, or build
command is required. A custom domain can be added later without rewriting the
site because all internal links are relative.

## Required before App Store submission

Search the site for `before public` and `To be supplied`. Replace those draft
notices with:

- the final legal operator identity; and
- a working private support email that the operator is comfortable publishing.

Then reconcile the hosted text with the current app implementation and App
Store privacy disclosures. Do not publish personal contact information by
guessing or copying it from Git configuration.
