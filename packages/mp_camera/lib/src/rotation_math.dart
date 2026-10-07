/// Normalizes a rotation in degrees to the range 0–359.
///
/// Shared by rotation resolution and frame conversion so both agree on how
/// negative and over-360 inputs fold into a canonical quarter turn.
int normalizeRotationDegrees(int value) => ((value % 360) + 360) % 360;
