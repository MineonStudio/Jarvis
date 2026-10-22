# Mahjong audio

The independent Mahjong window owns audio playback. Music, effects, and speech
have separate volume controls plus an overall volume and mute switch. Preferences
are stored locally under `mahjong.audio.*`. All four volume defaults are 50%;
restoring defaults uses these values without overwriting saved choices on launch.
Audio always pauses when the game window loses focus or the app enters the
background. Music resumes on return; old background-pause preferences are removed.
Closing/hiding the game stops every bus; leaving a round stops current speech.

## Restrained playback

There are eight effect types: draw, discard, deal, chi, pong, kong,
one deadline reminder, and a quiet result cue when speech is muted. Hovering,
selecting tiles, opening panels, button presses, ready status, turn changes,
response availability, multiplier choices, rewards, and player arrivals/departures
have no additional effects. Pre-round shuffling and dice rolls are silent.
Visual feedback and spoken game calls remain.

Actions trigger their tile contact and spoken call immediately in the same event
handler. Neither channel waits for another sound to finish. At most one effect
and one voice play together; tile effects are reduced to 55% during speech, and
music ducks under either channel. A new spoken call immediately replaces older
speech of equal or lower priority. Lower priority speech is dropped while an
important call plays. There is no speech queue and no delayed replay.

Claims supersede tile names; winning calls supersede claims; a pass cannot cut
off a tile name. Matching action effects still play immediately even when their
spoken call is dropped. Low priority countdown reminders are suppressed during
speech. Other effects retain their priority gate, never building a playback queue.
Deal contacts are limited to one per half second, and each state update contributes
at most one effect. The local deadline gives one soft reminder in the last three
seconds, with no per-second ticking or extra timeout jingle. Wins/round draws use
their spoken call alone; the result cue is a fallback when voice volume is zero.
Effects preview plays one pong contact. Voice previews use the selected “胡了”
recording without tile effects or a result jingle.

## Resources

`Resources/MahjongAudio/effects/` contains original synthesized tile
foley and restrained low-register cues. Draw/discard each have three variants.
Physical actions combine solid-body resonances, felt friction, clustered tile
landings, and irregular rolling impacts. Chi/pong/kong use tile foley rather than
musical chimes. The palette emphasizes bass and low mids with treble roll-off.
`music/happyTable.wav` is one original cheerful loop shared by the lobby and
table. It continues across match/menu transitions without restarting or crossfading.
The sixteen-bar C-major arrangement runs at 112 BPM with a rounded wood-key melody,
offbeat chord strokes, a bouncing bass, and soft percussion. It is generated with
the standard Python library:

```sh
python3 script/generate_mahjong_soundscape.py
```

The generator is deterministic and does not download recordings. WAV files are
mono 16-bit PCM at 32 kHz. Table effects are positioned in stereo according to the
player's relative seat. Existing male/female MP3 recordings remain the speech
source. `build_app.sh` copies this whole audio directory.

## Events and LAN

Claim/discard effects follow the authoritative voice events. Deal
and draw contacts follow the game state shared by solo play and LAN snapshots.
Audio does not change rules or network messages. Countdown reminders apply only
to a local decision. LAN speech is observed by the independent game window, so it
remains connected when the main Jarvis window navigates away from the plaza.
