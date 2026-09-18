# reem_front

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Google Sign-In Setup

To use Google Sign-In in this app:

1. Create an OAuth 2.0 Client ID in the Google Cloud Console:
   - Type: Web application
   - Authorized redirect URIs: leave blank for the Flutter plugin
2. Copy the client ID and replace `YOUR_WEB_CLIENT_ID.apps.googleusercontent.com`
   in `lib/services/google_sign_in_service.dart`.
3. For iOS, add the reversed client ID to
   `ios/Runner/Info.plist` under `CFBundleURLSchemes`.
4. For Android, register the package name `com.example.reem_front`
   in the Google Cloud Console and add the SHA-1 fingerprint if you use
   a release build.
5. Add `GOOGLE_CLIENT_ID=...` to the Laravel backend `.env` file.
