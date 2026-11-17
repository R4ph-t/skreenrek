import SkreenrekCore

/// Thin real implementations of the `SkreenrekCore` seams (ScreenCaptureKit, Accessibility, mouse monitors) arrive
/// in specs 02–04. Keep them thin: no logic a fake can't exercise.
public enum SkreenrekSystem {}
