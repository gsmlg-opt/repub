# How to Submit the dart2js Issue to Jaspr Team

## Issue Report File
The complete issue report has been prepared in: `JASPR_ISSUE_REPORT.md`

## Where to Submit

**Jaspr GitHub Issues**: https://github.com/schultek/jaspr/issues

## Submission Steps

1. **Visit the issues page**: https://github.com/schultek/jaspr/issues/new
2. **Title**: "dart2js production builds produce broken JavaScript with event handlers"
3. **Copy the content** from `JASPR_ISSUE_REPORT.md` into the issue body
4. **Add labels** (if available):
   - `bug` - This is a bug report
   - `build` - Related to build process
   - `dart2js` - Specific to dart2js compiler

## Additional Information to Include

When submitting, consider adding:

1. **Link to your repository** (if you're comfortable sharing):
   ```
   Repository: https://github.com/gsmlg-dev/repub
   Affected code: packages/repub_web/
   ```

2. **Your contact info** (if you want to be contacted for testing):
   - GitHub handle
   - Discord (Jaspr has a community Discord with 500+ members)

3. **Testing offer**:
   ```
   I'm happy to:
   - Provide additional logs or debugging info
   - Test proposed fixes
   - Create minimal reproduction case if needed
   - Grant access to our codebase for investigation
   ```

## Before Submitting - Check for Duplicates

Search existing issues first: https://github.com/schultek/jaspr/issues?q=dart2js

Keywords to search:
- dart2js
- production build
- event handlers
- form submission
- DDC vs dart2js

## Alternative: Discord Community

If you prefer to discuss first before filing an issue:
- Jaspr Discord community has 500+ developers
- Can get initial feedback on whether this is expected behavior
- Link should be available on the main repository or Jaspr website: https://jaspr.site/

## Expected Response

Based on the severity (blocks production deployments), you should expect:
1. Initial acknowledgment within a few days
2. Questions about reproduction steps or environment
3. Potential workarounds or configuration suggestions
4. Timeline for investigation/fix if confirmed as framework issue

## If It's a dart2js Issue (not Jaspr)

If the Jaspr team determines this is actually a dart2js bug, they may redirect you to:
- **Dart SDK Issues**: https://github.com/dart-lang/sdk/issues

In that case, they'll help determine if it's a dart2js bug or Jaspr's interaction with dart2js.

---

**Note**: The issue report has been carefully prepared with all necessary details. The Jaspr team should have everything they need to investigate and reproduce.
