/// Namespace holding the raw pixel-art source for every Hetzi animation.
///
/// Each animation state's frames live in a same-named extension file
/// (`MascotFrameData+Idle.swift`, `MascotFrameData+Walk.swift`, ...) to keep
/// this generated art auditable and reviewable in small chunks. Every frame
/// is a `[String]` of exactly 32 rows, each exactly 32 characters wide, where
/// each character names a `MascotPalette` entry ('.' transparent, 'k'
/// outline, 'r' rust, 'd' dark rust, 'c' cream, 'p' pink, 'w' white).
///
/// This is intentionally plain Swift source (no image assets, no JSON
/// resources) so the entire sprite atlas is a few tens of KB of text and
/// diffable like any other code.
enum MascotFrameData {}
