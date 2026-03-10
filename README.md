# nb mxsamples

this is an nb version of infinitedigits' mx.samples. zack, once again thank you so much for creating such a wonderful script.

nb mxsamples runs on the same files as mx.samples. the mx.samples script itself is not required but the samples need to be stored under `/audio/mx.samples/`. either install instrument samples via mx.samples or dowload them directly from the mx.samples [repo](https://github.com/schollz/mx.samples/releases/tag/samples) and copy them to norns.

---

**added/changed:**
- save and load presets
- max 12 voice polyphony
- fx via fx mod
- pitchbend via `nb:pitch_bend(note, val)` 
- modulation via `nb:modulate(val)` -> pairs well with sidvagn. morph filter cutoff and fx sends via modkey or `mod amt` parameter

**removed:**
- release sample feature
- internal fx bus


install and activate mod as ususal.
