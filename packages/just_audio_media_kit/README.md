# just_audio_media_kit local patch

This is the `just_audio_media_kit` 2.1.0 package source with one application
specific change: when the MPV player is ready, disable `sub-auto`. The
application loads lyrics through its own lyric project flow, so MPV must not
probe a neighboring `.lrc` file as an external subtitle when opening an audio
track.

All other playback behavior and dependencies remain unchanged from 2.1.0.
