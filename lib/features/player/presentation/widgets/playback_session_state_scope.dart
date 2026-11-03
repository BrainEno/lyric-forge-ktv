import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../domain/services/playback_session_service.dart';

/// Exposes the app-owned session stream to one playback-chrome subtree.
///
/// This forwards the existing session; it does not own or copy playback state.
class PlaybackSessionStateScope extends StatelessWidget {
  final PlaybackSessionService session;
  final Widget child;

  const PlaybackSessionStateScope({
    super.key,
    required this.session,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return StreamProvider<PlaybackSessionState>.value(
      value: session.stateStream,
      initialData: session.currentState,
      child: child,
    );
  }
}
