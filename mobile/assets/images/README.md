# assets/images

Intentionally empty. FrameMind draws its logo in code (`lib/core/widgets/app_logo.dart`)
and uses Material icons for platforms, so the app ships without binary image assets.

If you add images here, register the folder in `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/images/
```
