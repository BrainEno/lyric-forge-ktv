import 'package:flutter/material.dart';

import '../widgets/app_empty_state.dart';
import 'routes.dart';

/// Shown for a route name the routing table does not know.
///
/// Unknown names used to open the dashboard silently, so a stale link from an
/// old build or a typo in a deep link looked like a working jump to the
/// wrong page. This page says what happened, names the route so it can be
/// reported, and offers the way back.
class RouteNotFoundScreen extends StatelessWidget {
  const RouteNotFoundScreen({super.key, required this.routeName});

  /// The route name that was requested, as given to the navigator.
  final String routeName;

  @override
  Widget build(BuildContext context) {
    final navigator = Navigator.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('页面不存在')),
      body: Center(
        child: SingleChildScrollView(
          child: AppEmptyState(
            icon: Icons.explore_off_rounded,
            title: '找不到这个页面',
            message: '“$routeName”不对应任何页面，可能来自旧版本的链接或已经移除的功能。',
            actions: [
              FilledButton.icon(
                onPressed: () => navigator.pushNamedAndRemoveUntil(
                  Routes.home,
                  (route) => false,
                ),
                icon: const Icon(Icons.home_rounded),
                label: const Text('回到首页'),
              ),
              if (navigator.canPop())
                OutlinedButton.icon(
                  onPressed: navigator.pop,
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('返回上一页'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
