# [2026-11-19 11:25] Show a page for unknown routes

- Scope: UI/UX audit R-04. The routing table opened the dashboard for any name it did not know, so a stale link from an old build or a mistyped deep link looked like a working jump to the wrong page and left no trace. Unknown names (including unknown `/project/<id>/<page>` paths) now open "页面不存在" with the requested name, "回到首页" and, when there is a page behind it, "返回上一页"; the router logs a warning under the `router` tag.
- Files:
  - `lib/core/navigation/route_not_found_screen.dart` (new: `RouteNotFoundScreen` on `AppEmptyState`).
  - `lib/app/app_router.dart` (default branch logs and returns the new screen instead of the dashboard).
  - Test: `test/core/navigation/route_not_found_screen_test.dart` (new: unknown route and unknown project page through the production `AppRouter`, back, home).
- Validation:
  - No Dart/Flutter toolchain in the sandbox, so `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate. Every `Routes` constant has its own case and project paths keep their branches, so only names that matched nothing change behaviour.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - The router test passes the uninitialised `AppServices.instance` to `AppRouter`; unknown routes never read a service. `lib/app/` itself still does not reach the singleton.
  - The empty and missing route name (`null`) still means home.
- Commit: `Show a page for unknown routes`
