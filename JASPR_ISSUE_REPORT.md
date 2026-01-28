# Jaspr Issue Report: dart2js Production Builds Produce Broken JavaScript

**Issue**: Production builds using dart2js generate malformed JavaScript that breaks event handlers and form submissions in Jaspr applications.

## Summary

When building a Jaspr web application for production using dart2js (via `dart run webdev build`), the generated JavaScript contains errors that prevent event handlers from executing. Forms appear to render correctly but clicking submit buttons does nothing, and the browser console shows errors like "s.gag is not a function" and "A.k(...).gj7 is not a function".

The development build using DDC (dartdevc) works perfectly with all features functioning correctly.

## Environment

- **Jaspr Version**: 0.14.1
- **Dart SDK**: 3.6.0
- **Flutter SDK**: 3.27.1
- **Build System**: webdev 3.2.2
- **Compiler**: dart2js (production) vs dartdevc (development)
- **Platform**: macOS Darwin 25.2.0 (also reproduced on Linux)

## Build Configuration

`packages/repub_web/build.yaml`:
```yaml
targets:
  $default:
    builders:
      jaspr_builder:
        enabled: true
      build_web_compilers:entrypoint:
        generate_for:
          - web/main.dart
        release_options:
          compiler: dart2js
          dart2js_args:
            - -O2
        dev_options:
          compiler: dartdevc
```

## Steps to Reproduce

1. **Create a Jaspr app with forms** (e.g., registration/login forms)
2. **Build for development**: `dart run webdev serve` → Works perfectly ✅
3. **Build for production**: `dart run webdev build` → Forms are broken ❌
4. **Test the production build**:
   - Navigate to registration page
   - Fill out form fields
   - Click submit button
   - **Expected**: Form submits, validation occurs
   - **Actual**: Nothing happens, JavaScript errors in console

## Error Details

Browser console shows 78+ JavaScript errors:

```
Uncaught TypeError: s.gag is not a function
    at Object.bG (main.dart.js:26661:298)
    at Object.giu (main.dart.js:25729:33)
    at Object.git (main.dart.js:25728:99)
    ...

Uncaught TypeError: A.k(...).gj7 is not a function
    at gjy (main.dart.js:24892:79)
    at gjz (main.dart.js:24896:36)
    ...
```

The obfuscated function names suggest dart2js is producing incorrect code during compilation/optimization.

## Analysis

### What Works (DDC - Development)
- All form submissions work correctly
- Event handlers fire as expected
- Complete E2E user flows function: registration → authentication → token creation → package publishing → downloading
- JavaScript is readable and debuggable

### What Fails (dart2js - Production)
- Forms render but don't submit
- Click handlers appear to be missing or broken
- Navigation works (router is fine)
- Static content displays correctly
- Only interactive elements (forms, buttons with event handlers) are affected

### Attempted Solutions

We've tried multiple configurations, all still produce broken JavaScript:

1. ❌ **Removed minification**: Still broken
   ```yaml
   dart2js_args:
     - -O2
   ```

2. ❌ **Disabled all optimizations**: Still broken
   ```yaml
   dart2js_args: []
   ```

3. ❌ **Used different optimization levels**: All levels (-O0 through -O4) produce errors

4. ✅ **Switched to DDC**: Works perfectly (but not suitable for production)

## Code Example

Minimal reproduction case (simplified from our actual app):

`lib/pages/register.dart`:
```dart
import 'package:jaspr/jaspr.dart';

class RegisterPage extends StatelessComponent {
  @override
  Iterable<Component> build(BuildContext context) sync* {
    yield form([
      input(
        [type('email'), name('email'), placeholder('Email')],
      ),
      input(
        [type('password'), name('password'), placeholder('Password')],
      ),
      button(
        [type('submit')],
        [text('Register')],
      ),
    ], attributes: [
      FormAction.post('/api/register'),
    ]);
  }
}
```

This simple form works in development but fails in production builds.

## Workaround

Currently using `melos run dev` (DDC compiler) for both development and production, deployed behind a reverse proxy. This works but defeats the purpose of production builds.

## Expected Behavior

Production builds using dart2js should generate functional JavaScript that matches the behavior of development builds using DDC.

## Actual Behavior

dart2js generates malformed JavaScript with broken event handlers, making forms and interactive elements non-functional.

## Additional Context

- This affects a real-world production application (self-hosted Dart package registry)
- The same code works perfectly when compiled with DDC
- Issue appears to be specific to dart2js + Jaspr combination
- Other Jaspr features (routing, components, rendering) work correctly with dart2js
- Only event handlers and form submissions are affected

## Request

1. Investigate dart2js compatibility with Jaspr's event handling system
2. Provide guidance on proper dart2js configuration for production builds
3. Consider documenting known limitations or recommended build configurations
4. If this is a dart2js bug, consider reporting upstream to Dart team

## Testing Availability

We have a complete reproduction case available in our repository:
- Repository: https://github.com/gsmlg-dev/repub
- Affected package: `packages/repub_web`
- Build commands: `melos run build:web` (fails) vs `melos run dev:web` (works)
- E2E test suite available for validation

Happy to provide additional information, logs, or access to our codebase for debugging.

---

**Reported by**: Repub team
**Date**: 2026-01-29
**Severity**: High (blocks production deployment with recommended build tools)
